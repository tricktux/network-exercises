const std = @import("std");
const messages = @import("messages.zig");
const time = @import("time.zig");
const types = @import("types.zig");
const linux = std.os.linux;

const u8BoundedArray = types.u8BoundedArray;
const Message = messages.Message;
const socketfd = types.socketfd;
const CameraHashMap = std.AutoHashMap(std.posix.socket_t, Camera);
const RoadHashMap = std.AutoHashMap(u16, Road);
const ArrayCameraId = std.ArrayList(socketfd);
const String = std.ArrayList(u8);
pub const TicketsQueue = std.ArrayList(Message); // Of Type.Ticket
const Tickets = std.StringHashMap(Message);
const Observations = std.ArrayList(Observation);
const ObservationsHashMap = std.StringHashMap(Observations);
const ObservationsKeysStore = std.SinglyLinkedList([]u8);
const CarHashMap = std.StringHashMap(Car);
const ClientHashMap = std.AutoHashMap(socketfd, Client);
const EpollEventsArray = std.BoundedArray(linux.epoll_event, 256);
const TimerHashMap = std.AutoHashMap(socketfd, Timer);

pub const Context = struct {
    cars: *Cars,
    roads: *Roads,
    cameras: *Cameras,
    tickets: *TicketsQueue,
    clients: *Clients,
    epoll: *EpollManager,
    timers: *Timers,
};

pub const Timer = struct {
    fd: socketfd,
    client: *Client,
    interval: u64, // In deciseconds

    pub fn init(client: *Client, interval: u64) !Timer {
        const timerfd = try std.posix.timerfd_create(std.posix.CLOCK.MONOTONIC, std.posix.TFD.CLOEXEC | std.posix.TFD.NONBLOCK);

        // Convert deciseconds to nanoseconds (1 decisecond = 100,000,000 nanoseconds)
        const interval_ns = interval * 100_000_000;

        const itimerspec = std.posix.itimerspec{
            .it_interval = .{ .tv_sec = interval_ns / 1_000_000_000, .tv_nsec = interval_ns % 1_000_000_000 },
            .it_value = .{ .tv_sec = interval_ns / 1_000_000_000, .tv_nsec = interval_ns % 1_000_000_000 },
        };

        try std.posix.timerfd_settime(timerfd, 0, &itimerspec, null);
        return Timer{
            .fd = timerfd,
            .client = client,
            .interval = interval_ns,
        };
    }

    pub fn deinit(self: *Timer) void {
        _ = std.posix.close(self.fd);
    }
};

pub const Timers = struct {
    map: TimerHashMap,
    mutex: std.Thread.Mutex = .{},

    pub fn init(alloc: std.mem.Allocator) !Timers {
        return Timers{
            .map = TimerHashMap.init(alloc),
        };
    }

    pub fn deinit(self: *Timers) void {
        self.map.deinit();
    }

    pub fn add(self: *Timers, timer: Timer) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.map.put(timer.fd, timer);
    }

    pub fn get(self: *Timers, fd: socketfd) ?*Timer {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.map.getPtr(fd);
    }

    pub fn del(self: *Timers, fd: socketfd) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.fetchRemove(fd)) |timer| {
            timer.value.deinit();
        } else {
            std.log.err("Error removing timer with fd: {d}\n", .{fd});
        }
    }
};

pub const ClientType = enum {
    Camera,
    Dispatcher,
};

pub const EpollManager = struct {
    epollfd: socketfd,
    event_flags: u32 = linux.EPOLL.IN | linux.EPOLL.ET | linux.EPOLL.RDHUP | linux.EPOLL.ONESHOT,

    pub fn init() !EpollManager {
        const epollfd = try std.posix.epoll_create1(0);
        return EpollManager{
            .epollfd = epollfd,
        };
    }

    pub fn deinit(self: *EpollManager) void {
        _ = std.posix.close(self.epollfd);
    }

    pub fn add(self: *EpollManager, fd: socketfd) !void {
        var event = linux.epoll_event{
            .events = self.event_flags,
            .data = .{ .fd = fd },
        };

        try std.posix.epoll_ctl(self.epollfd, linux.EPOLL.CTL_ADD, fd, &event);
    }

    pub fn mod(self: *EpollManager, fd: socketfd) !void {
        var event = linux.epoll_event{
            .events = self.event_flags,
            .data = .{ .fd = fd },
        };
        try std.posix.epoll_ctl(self.epollfd, linux.EPOLL.CTL_MOD, fd, &event);
    }

    pub fn del(self: *EpollManager, fd: socketfd) !void {
        try std.posix.epoll_ctl(self.epollfd, linux.EPOLL.CTL_DEL, fd, null);
    }
};

pub const Clients = struct {
    map: ClientHashMap,
    mutex: std.Thread.Mutex = .{},

    pub fn init(alloc: std.mem.Allocator) !Clients {
        return Clients{
            .map = ClientHashMap.init(alloc),
        };
    }

    pub fn deinit(self: *Clients, epoll: *EpollManager) !void {
        var it = self.map.iterator();
        while (it.next()) |client| {
            try client.value_ptr.deinit(epoll);
        }

        self.map.deinit();
    }

    pub fn add(self: *Clients, client: Client, epoll: *EpollManager) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        epoll.add(client.fd);
        try self.map.put(client.fd, client);
    }

    pub fn get(self: *Clients, fd: socketfd) ?*Client {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.getPtr(fd);
    }

    pub fn del(self: *Clients, fd: socketfd, epoll: *EpollManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.fetchRemove(fd)) |client| {
            client.value.deinit(epoll);
        } else {
            std.log.err("Error removing client with fd: {d}\n", .{fd});
        }
    }
};

pub const Client = struct {
    fd: socketfd,
    type: ClientType,
    timer: ?Timer,
    data: union(enum) {
        camera: Camera,
        dispatcher: Dispatcher,
    },

    pub fn initWithCamera(fd: socketfd, message: Message) !Client {
        if (message.type != messages.Type.IAmCamera) return LogicError.MessageWrongType;
        std.log.info("Creating camera client: road: {d}, mile: {d}, limit: {d}\n", .{ message.data.camera.road, message.data.camera.mile, message.data.camera.limit });

        return Client{
            .fd = fd,
            .type = ClientType.Camera,
            .data = .{ .camera = Camera.initFromMessage(fd, message) },
        };
    }

    pub fn initWithDispatcher(fd: socketfd, message: Message) !Client {
        if (message.type != messages.Type.IAmDispatcher) return LogicError.MessageWrongType;
        std.log.info("Creating dispatcher client with fd: {d}\n", .{fd});
        return Client{
            .fd = fd,
            .type = ClientType.Dispatcher,
            .data = .{ .dispatcher = Dispatcher.initFromMessage(fd, message) },
        };
    }

    pub fn addTimer(self: *Client, interval: u64, epoll: *EpollManager) !void {
        if (self.timer != null) return LogicError.AlreadyHasTimer;

        std.log.info("Adding timer to client with interval: {d}\n", .{interval});
        self.timer = try Timer.init(self, interval);
        epoll.add(self.timer.?.fd);
    }

    pub fn sendHeartbeat(self: *Client) !void {
        const m = Message.initHeartbeat();
        const buf = u8BoundedArray.init(0);
        std.log.debug("Sending heartbeat to client with fd: {d}\n", .{self.fd});
        _ = try m.host_to_network(m, &buf);
        const result = try std.posix.write(self.fd, buf.constSlice());
        if (result != buf.len) {
            std.log.err("Error sending heartbeat to client with fd: {}\n", .{self.fd});
        }
    }

    pub fn deinit(self: *Client, epoll: *EpollManager) !void {
        if (self.timer != null) {
            try epoll.del(self.timer.?.fd);
            self.timer.?.deinit();
        }

        epoll.del(self.fd) catch |err| {
            std.log.err("Error removing client from epoll: {}\n", .{err});
        };
        _ = std.posix.close(self.fd);
        switch (self.data) {
            .dispatcher => self.data.dispatcher.deinit(),
            else => {},
        }
    }
};

pub const Dispatcher = struct {
    fd: socketfd,
    roads: std.ArrayList(u16),

    pub fn initFromMessage(fd: socketfd, message: Message) !Dispatcher {
        if (message.type != messages.Type.IAmDispatcher) return LogicError.MessageWrongType;

        return Camera{
            .fd = fd,
            .roads = message.roads.toOwnedSlice(),
        };
    }

    pub fn deinit(self: *Dispatcher) void {
        self.roads.deinit();
    }
};

pub const Observation = struct {
    timestamp: time.DateTime,
    road: u16,
    mile: u16,
    speed_limit: u16,

    fn lessThan(_: void, a: Observation, b: Observation) bool {
        return a.timestamp.toUnixMilli() < b.timestamp.toUnixMilli();
    }
};

pub const Car = struct {
    plate: String,
    tickets_queue: *TicketsQueue,
    tickets: Tickets, // Non owning list of all observations keys that cause a
    // ticket. For easy check if a car has a ticket on this road, on this date
    observationsmap: ObservationsHashMap,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, tickets: *TicketsQueue) !Car {
        return Car{
            .plate = try String.initCapacity(alloc, 32),
            .tickets_queue = tickets,
            .tickets = try Tickets.initCapacity(alloc, 4),
            .observationsmap = try ObservationsHashMap.init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Car) void {
        self.plate.deinit();
        // self.tickets.deinit();
        var it = self.observationsmap.iterator();
        while (it.next()) |observations| {
            observations.value_ptr.deinit();
            self.alloc.free(observations.key_ptr.*);
        }
        self.observationsmap.deinit();
    }

    fn createUniqueKey(road: u16, timestamp: time.DateTime, buf: []const u8) ![]u8 {
        return try std.fmt.bufPrint(&buf, "{d}-{MM/dd/YYYY}", .{ road, timestamp });
    }

    // TODO: Check after calling this function the global tickets_queue and send
    // them out
    pub fn addObservation(self: *Car, message: Message, cam: *Camera) !void {
        if (message.type != messages.Type.Plate) return LogicError.MessageWrongType;
        if (message.data.plate.len == 0) return LogicError.EmptyPlate;
        if (self.plate.items.len == 0) return LogicError.EmptyPlate;
        if (!std.mem.eql(u8, message.data.plate, self.plate.items)) return LogicError.PlateMismatch;

        const timestamp = time.timestamp_to_date(message.timestamp);

        // Get the unique key for this observation
        const buf: [1024]u8 = undefined;
        const key = try createUniqueKey(cam.road, timestamp, &buf);
        std.log.info("Adding observation to car with plate: {s}, timestamp: {time.format.lll}, road: {d}, mile: {d}, limit: {d}", .{ self.plate.items, message.timestamp, cam.road, cam.mile, cam.speed_limit });
        const o = Observation{ .timestamp = timestamp, .road = cam.road, .mile = cam.mile, .speed_limit = cam.speed_limit };

        // Add to observations map or create a new one key
        var observations: Observations = undefined;
        if (self.observationsmap.contains(key)) {
            // Just add it to the existing list
            var obs = self.observationsmap.get(key).?;
            try obs.append(o);
            observations = obs;
        } else {
            // Create a permanent copy of the key
            const key_dupe = try self.alloc.dupe(u8, key);

            // Add it to the observation to the map
            var obs = try Observations.initCapacity(self.alloc, 4);
            try obs.append(o);
            try self.observationsmap.put(key_dupe, obs);
            return;
        }

        // TODO: Get only the day portion of and that's what you save on tickets
        // - Because you could have a ticket for a different road on the same
        const idx = std.mem.indexOf(u8, key, '-');
        if (idx == null) {
            std.log.err("Error parsing key: {s}\n", .{key});
            return;
        }
        // TODO: Change tickets to StringHashMap of day of ticket to ticket
        // - To make this line below just a contains
        // day
        // Check if we've already issued a ticket for this road and date
        const date_key = key[0..idx.?];
        if (self.tickets.contains(date_key)) {
            // We've already issued a ticket for this road/date
            std.log.info("Ticket already issued for car on this date: {s}", .{ date_key });
            return;
        }
        // var ticket_it = self.tickets.first;
        // while (ticket_it) |node| : (ticket_it = node.next) {
        //     if (std.mem.eql(u8, node.data, key)) {
        //         // We've already issued a ticket for this road/date
        //         std.log.info("Ticket already issued for car with plate: {s} on road: {d}", .{ self.plate.items, cam.road });
        //         return;
        //     }
        // }

        // Sort observations by timestamp
        std.sort.block(Observation, observations.items, {}, Observation.lessThan);

        // We have more than one observation on the same day on the same road
        // Check if there has been a violation
        // - If there's an entry we aleady issued a ticket for this date. return
        // TODO: Compute speed as (mile2 - mile1)/(time2 - time1)
        // TODO: If speed > speed_limit, add ticket to tickets_queue and to tickets list
        // Compute speed for each pair of observations
        for (observations.items, 0..) |_, i| {
            if (i == 0) continue; // Skip first observation, we need pairs

            const obs1 = observations.items[i - 1];
            const obs2 = observations.items[i];

            // Calculate time difference in hours
            const time_diff_ms = obs2.timestamp.toUnixMilli() - obs1.timestamp.toUnixMilli();
            const time_diff_hours = @as(f64, time_diff_ms) / (1000.0 * 60.0 * 60.0);

            // Skip if time difference is too small to avoid division by zero
            if (time_diff_hours <= 0.0001) continue;

            // Calculate distance in miles (absolute value)
            const distance = @as(f64, if (obs2.mile > obs1.mile) obs2.mile - obs1.mile else obs1.mile - obs2.mile);

            // Calculate speed in miles per hour
            const speed = distance / time_diff_hours;

            // Check if speed exceeds the limit
            if (speed > @as(f64, obs1.speed_limit)) {
                // Create a new ticket
                // TODO: fix here
                var ticket = Message.initTicket();
                ticket.data.ticket.plate = self.plate.items;
                ticket.data.ticket.road = cam.road;
                ticket.data.ticket.mile1 = obs1.mile;
                ticket.data.ticket.timestamp1 = obs1.timestamp.toUnixMilli();
                ticket.data.ticket.mile2 = obs2.mile;
                ticket.data.ticket.timestamp2 = obs2.timestamp.toUnixMilli();
                ticket.data.ticket.speed = @as(u16, speed + 0.5); // Round to nearest integer

                // Add the ticket to the global queue
                try self.tickets_queue.*.append(ticket);

                // Add the key to our tickets list to mark that we've issued a ticket for this road/date
                // const key_dupe = try self.alloc.dupe(u8, key);
                // var node = try self.alloc.create(std.SinglyLinkedList([]u8).Node);
                // node.* = .{ .data = key_dupe, .next = null };
                // self.tickets.prepend(node);

                std.log.info("Issued ticket for car with plate: {s}, road: {d}, speed: {d}/{d}", .{ self.plate.items, cam.road, ticket.data.ticket.speed, obs1.speed_limit });

                // Only issue one ticket per day per road
                return;
            }
        }
    }
};

pub const LogicError = error{
    EmptyPlate,
    MessageWrongType,
    AlreadyHasTimer,
    PlateMismatch,
};

pub const Cars = struct {
    map: CarHashMap,
    tickets_queue: *TicketsQueue,
    mutex: std.Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, tickets: *TicketsQueue) !Cars {
        return Cars{
            .map = CarHashMap.init(alloc),
            .tickets_queue = tickets,
            .allocator = alloc,
        };
    }

    pub fn deinit(self: *Cars) void {
        var it = self.map.iterator();

        while (it.next()) |car| {
            car.value_ptr.deinit();
        }

        self.map.deinit();
    }

    pub fn add(self: *Cars, plate: []const u8) !void {
        if (plate.len == 0) return LogicError.EmptyPlate;

        self.mutex.lock();
        defer self.mutex.unlock();

        var car = try Car.init(self.allocator, self.tickets_queue);
        car.plate.appendSlice(plate);
        try self.map.put(car.plate.items, car);
    }

    pub fn get(self: *Cars, plate: []const u8) !?*Car {
        if (plate.len == 0) return LogicError.EmptyPlate;

        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.getPtr(plate);
    }

    pub fn del(self: *Cars, plate: []const u8) void {
        if (plate.len == 0) return LogicError.EmptyPlate;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.fetchRemove(plate)) |car| {
            car.value.deinit();
        } else {
            std.log.err("Error removing car with plate: {s}\n", .{plate});
        }
    }
};

pub const Road = struct {
    road: u16,
    speed_limit: ?u16 = null,
    dispatcher: ?socketfd = null, // Dispatcher associated with this road
    cameras: ArrayCameraId, // Cameras associated with this road

    pub fn init(alloc: std.mem.Allocator) !Road {
        return Road{
            .cameras = ArrayCameraId.initCapacity(alloc, 4),
        };
    }

    pub fn deinit(self: *Road) void {
        self.cameras.deinit();
    }

    pub fn addCameraId(self: *Road, camid: socketfd) !void {
        try self.cameras.append(camid);
    }

    pub fn delCameraId(self: *Road, camid: socketfd) void {
        const it = self.cameras.iterator();
        while (it.next()) |id| {
            if (id == camid) {
                _ = self.cameras.remove(it.index());
                break;
            }
        }
    }
};

pub const Roads = struct {
    map: RoadHashMap,
    mutex: std.Thread.Mutex = .{},

    pub fn init(alloc: std.mem.Allocator) !Roads {
        return Roads{
            .map = RoadHashMap.init(alloc),
        };
    }

    pub fn deinit(self: *Roads) void {
        self.map.deinit();
    }

    // TODO: do we need a client here?
    pub fn add(self: *Roads, road: Road) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.map.put(road.road, road);
    }

    pub fn get(self: *Roads, road: u16) ?*Road {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.getPtr(road);
    }

    pub fn del(self: *Roads, road: u16) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.fetchRemove(road)) |r| {
            r.value.deinit();
        } else {
            std.log.err("Error removing road with id: {d}\n", .{road});
        }
    }
};

pub const Camera = struct {
    fd: socketfd,
    road: u16,
    mile: u16,
    speed_limit: u16,

    pub fn initFromMessage(fd: socketfd, message: Message) !Camera {
        if (message.type != messages.Type.IAmCamera) return LogicError.MessageWrongType;

        return Camera{
            .fd = fd,
            .road = message.road,
            .mile = message.mile,
            .speed_limit = message.limit,
        };
    }
};

pub const Cameras = struct {
    map: CameraHashMap,
    mutex: std.Thread.Mutex = .{},

    pub fn init(alloc: std.mem.Allocator) !Cameras {
        return Cameras{
            .map = CameraHashMap.init(alloc),
        };
    }

    pub fn deinit(self: *Cameras) void {
        self.map.deinit();
    }

    pub fn add(self: *Cameras, camera: Camera) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.map.put(camera.key, camera);
    }

    pub fn get(self: *Cameras, fd: socketfd) ?*Camera {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.getPtr(fd);
    }

    pub fn del(self: *Cameras, fd: socketfd) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.fetchRemove(fd)) |cam| {
            cam.value.deinit();
        } else {
            std.log.err("Error removing camera with id: {d}\n", .{fd});
        }
    }
};
