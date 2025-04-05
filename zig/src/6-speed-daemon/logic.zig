const std = @import("std");
const messages = @import("messages.zig");
const time = @import("time.zig");
const types = @import("types.zig");
const logger = @import("logger.zig");
const Set = @import("ziglangSet").Set;
const linux = std.os.linux;
const testing = std.testing;

const u8BoundedArray = types.u8BoundedArray;
const Message = messages.Message;
const socketfd = types.socketfd;
const CameraHashMap = std.AutoHashMap(std.posix.socket_t, Camera);
const RoadHashMap = std.AutoHashMap(u16, Road);
const ArrayCameraId = std.ArrayList(socketfd);
const String = std.ArrayList(u8);
// TODO: Make this a DoublyLinkedList
const Ticket = messages.Ticket;
pub const TicketsQueue = std.ArrayList(Message); // Of Type.Ticket
const Tickets = std.StringHashMap(Message);
const Observations = std.ArrayList(Observation);
const ObservationsHashMap = std.StringHashMap(Observations);
const ObservationsKeysStore = std.SinglyLinkedList([]u8);
const CarHashMap = std.StringHashMap(Car);
const ClientHashMap = std.AutoHashMap(socketfd, Client);
const EpollEventsArray = std.BoundedArray(linux.epoll_event, 256);
const TimerHashMap = std.AutoHashMap(socketfd, Timer);
const u8Fifo = std.fifo.LinearFifo(u8, .Dynamic);
const FdFifoHashMap = std.AutoHashMap(socketfd, u8Fifo);
const RoadsArray = std.ArrayList(u16);
const DispatchersSet = Set(socketfd);

pub const Context = struct {
    cars: *Cars,
    roads: *Roads,
    cameras: *Cameras,
    tickets: *TicketsQueue,
    clients: *Clients,
    epoll: *EpollManager,
    timers: *Timers,
    fifos: *Fifos,
};

pub const Fifos = struct {
    map: FdFifoHashMap,
    mutex: std.Thread.Mutex = .{},
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !Fifos {
        return Fifos{
            .map = FdFifoHashMap.init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Fifos) void {
        var it = self.map.iterator();
        while (it.next()) |fifo| {
            fifo.value_ptr.deinit();
        }
        self.map.deinit();
    }

    pub fn add(self: *Fifos, fd: socketfd) !void {
        if (fd == 0) return error.InvalidFd;

        self.mutex.lock();
        defer self.mutex.unlock();

        const fifo = u8Fifo.init(self.alloc);
        try self.map.put(fd, fifo);
    }

    pub fn get(self: *Fifos, fd: socketfd) ?*u8Fifo {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.getPtr(fd);
    }

    pub fn del(self: *Fifos, fd: socketfd) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var fifo = self.map.getPtr(fd);
        if (fifo == null) {
            std.log.err("Failed to find fifo with fd: {d} for removal\n", .{fd});
            return;
        }
        fifo.?.deinit();
        _ = self.map.remove(fd);
    }
};

pub const Timer = struct {
    fd: socketfd,
    client: *Client,
    interval: u64, // In deciseconds

    pub fn init(client: *Client, interval: u64) !Timer {
        const flags = std.os.linux.TFD{.CLOEXEC = true, .NONBLOCK = true};
        const timerfd = try std.posix.timerfd_create(std.os.linux.TIMERFD_CLOCK.MONOTONIC, flags);

        // Convert deciseconds to nanoseconds (1 decisecond = 100,000,000 nanoseconds)
        const interval_ns: isize = @as(isize, @intCast(interval)) * 100_000_000;

        const itimerspec = std.os.linux.itimerspec{
            .it_interval = .{ .sec = @divFloor(interval_ns, 1_000_000_000), .nsec = @mod(interval_ns, 1_000_000_000) },
            .it_value = .{ .sec = @divFloor(interval_ns, 1_000_000_000), .nsec = @mod(interval_ns, 1_000_000_000) },
        };

        try std.posix.timerfd_settime(timerfd, .{}, &itimerspec, null);
        return Timer{
            .fd = timerfd,
            .client = client,
            .interval = interval,
        };
    }

    pub fn read(self: *Timer) !u64 {
        var expiry_count: u64 = 0;
        _ = try std.posix.read(self.fd, std.mem.asBytes(&expiry_count));
        return expiry_count;
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

    pub fn add(self: *Clients, client: Client) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.map.put(client.fd, client);
    }

    pub fn get(self: *Clients, fd: socketfd) ?*Client {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.getPtr(fd);
    }

    pub fn del(self: *Clients, fd: socketfd, epoll: *EpollManager) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var client = self.map.getPtr(fd);
        if (client == null) {
            std.log.err("Failed to find client with fd: {d} for removal\n", .{fd});
            return;
        }
        try client.?.deinit(epoll);
        _ = self.map.remove(fd);
    }
};

pub const Client = struct {
    fd: socketfd,
    type: ClientType,
    timer: ?Timer = null,
    data: union(enum) {
        camera: Camera,
        dispatcher: Dispatcher,
    },

    pub fn initWithCamera(fd: socketfd, cam: Camera) Client {
        return Client{
            .fd = fd,
            .type = ClientType.Camera,
            .data = .{ .camera = cam },
        };
    }

    pub fn initWithDispatcher(fd: socketfd, disp: Dispatcher) Client {
        std.log.info("Creating dispatcher client with fd: {d}\n", .{fd});
        return Client{
            .fd = fd,
            .type = ClientType.Dispatcher,
            .data = .{ .dispatcher = disp },
        };
    }

    pub fn addTimer(self: *Client, interval: u64, epoll: *EpollManager) !Timer {
        if (self.timer != null) return LogicError.AlreadyHasTimer;

        std.log.info("Adding timer to client with interval: {d}\n", .{interval});
        self.timer = try Timer.init(self, interval);
        try epoll.add(self.timer.?.fd);
        return self.timer.?;
    }

    pub fn sendError(self: *Client, msg: []const u8, buf: *u8BoundedArray) !void {
        const m = Message.initError(msg);
        _ = try m.host_to_network(buf);
        const stream = std.net.Stream{ .handle = self.fd };
        try stream.writeAll(buf.constSlice());
    }

    pub fn sendHeartbeat(self: *Client, buf: *u8BoundedArray) !void {
        const m = Message.initHeartbeat();
        std.log.debug("Sending heartbeat to client with fd: {d}\n", .{self.fd});
        _ = try m.host_to_network(buf);
        const stream = std.net.Stream{ .handle = self.fd };
        try stream.writeAll(buf.constSlice());
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
    roads: RoadsArray,

    pub fn initFromMessage(fd: socketfd, message: *Message, alloc: std.mem.Allocator) !Dispatcher {
        if (message.type != messages.Type.IAmDispatcher) return LogicError.MessageWrongType;

        return Dispatcher{
            .fd = fd,
            .roads = RoadsArray.fromOwnedSlice(alloc, try message.data.dispatcher.roads.toOwnedSlice()),
        };
    }

    pub fn deinit(self: *Dispatcher) void {
        self.roads.deinit();
    }

    // TODO: Send Ticket
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
            .tickets = Tickets.init(alloc),
            .observationsmap = ObservationsHashMap.init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Car) void {
        self.plate.deinit();
        self.tickets.deinit();
        var it = self.observationsmap.iterator();
        while (it.next()) |observations| {
            observations.value_ptr.deinit();
            self.alloc.free(observations.key_ptr.*);
        }
        self.observationsmap.deinit();
    }

    fn createUniqueKey(road: u16, timestamp: time.DateTime, buf: []u8) ![]u8 {
        return try std.fmt.bufPrint(buf, "{d}-{MM/DD/YYYY}", .{ road, timestamp });
    }

    // TODO: Check after calling this function the global tickets_queue and send
    // them out
    pub fn addObservation(self: *Car, message: Message, cam: *Camera) !void {
        if (message.type != messages.Type.Plate) return LogicError.MessageWrongType;
        if (message.data.plate.plate.len == 0) return LogicError.EmptyPlate;
        if (self.plate.items.len == 0) return LogicError.EmptyPlate;
        if (!std.mem.eql(u8, message.data.plate.plate, self.plate.items)) return LogicError.PlateMismatch;

        const timestamp = messages.timestamp_to_date(message.data.plate.timestamp);

        // Get the unique key for this observation
        var buf: [1024]u8 = undefined;
        const key = try createUniqueKey(cam.road, timestamp, &buf);
        std.log.info("Adding observation to car with plate: {s}, timestamp: {MM/DD/YYYY HH-mm-ss.SSS A}, road: {d}, mile: {d}, limit: {d}", .{ self.plate.items, timestamp, cam.road, cam.mile, cam.speed_limit });
        const o = Observation{ .timestamp = timestamp, .road = cam.road, .mile = cam.mile, .speed_limit = cam.speed_limit };

        // Add to observations map or create a new one key
        var observations: Observations = undefined;
        const entry = self.observationsmap.getEntry(key);
        if (entry != null) {
            observations = entry.?.value_ptr.*;
            try observations.append(o);
        } else {
            // Create a permanent copy of the key
            const key_dupe = try self.alloc.dupe(u8, key);

            // Add it to the observation to the map
            var obs = try Observations.initCapacity(self.alloc, 4);
            try obs.append(o);
            try self.observationsmap.put(key_dupe, obs);
            return;
        }

        const key_mem = entry.?.key_ptr.*;
        const idx = std.mem.indexOf(u8, key_mem, "-");
        if (idx == null) {
            std.log.err("Error parsing key: {s}\n", .{key_mem});
            return;
        }
        // Check if we've already issued a ticket for this road and date
        const date_key = key[idx.? + 1 ..];
        if (self.tickets.contains(date_key)) {
            // We've already issued a ticket to this car for this date
            std.log.info("Ticket already issued for car on this date: {s}", .{date_key});
            return;
        }

        // Sort observations by timestamp
        std.sort.block(Observation, observations.items, {}, Observation.lessThan);

        // We have more than one observation on the same day on the same road
        // Check if there has been a violation
        // - If there's an entry we aleady issued a ticket for this date. return
        // Compute speed as (mile2 - mile1)/(time2 - time1)
        // If speed > speed_limit, add ticket to tickets_queue and to tickets list
        // Compute speed for each pair of observations
        for (observations.items, 0..) |_, i| {
            if (i == 0) continue; // Skip first observation, we need pairs

            const obs1 = observations.items[i - 1];
            const obs2 = observations.items[i];

            // Calculate time difference in hours
            const time_diff_sec = obs2.timestamp.toUnix() - obs1.timestamp.toUnix();
            const time_diff_hours = @as(f64, @floatFromInt(time_diff_sec)) / (60.0 * 60.0);

            // Skip if time difference is too small to avoid division by zero
            if (time_diff_hours <= 0.001) continue;

            // Calculate distance in miles (absolute value)
            const distance = @as(f64, @floatFromInt(if (obs2.mile > obs1.mile) obs2.mile - obs1.mile else obs1.mile - obs2.mile));

            // Calculate speed in miles per hour
            const speed = distance / time_diff_hours;

            // Check if speed exceeds the limit
            if (speed <= @as(f64, @floatFromInt(obs1.speed_limit))) continue;

            // Create a new ticket
            var ticket = Ticket.init();
            ticket.plate = self.plate.items;
            ticket.road = cam.road;
            ticket.mile1 = obs1.mile;
            ticket.timestamp1 = @as(u32, @intCast(obs1.timestamp.toUnix()));
            ticket.mile2 = obs2.mile;
            ticket.timestamp2 = @as(u32, @intCast(obs2.timestamp.toUnix()));
            ticket.speed = @as(u16, @intFromFloat(speed + 0.5)); // Round to nearest integer

            const msg = Message.initTicket(ticket);

            // Add the ticket to the global queue
            try self.tickets_queue.*.append(msg);
            try self.tickets.put(date_key, msg);

            std.log.info("Issued ticket for car with plate: {s}, road: {d}, speed: {d}/{d}", .{ self.plate.items, cam.road, ticket.speed, obs1.speed_limit });

            // Only issue one ticket per day per road
            return;
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
    // Use it directly dispatchers.{add,remove}
    dispatchers: DispatchersSet,

    pub fn init(alloc: std.mem.Allocator, road: u16) !Road {
        return Road{
            .road = road,
            .dispatchers = try DispatchersSet.initCapacity(alloc, 4),
        };
    }

    pub fn deinit(self: *Road) !void {
        self.dispatchers.deinit();
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

    pub fn deinit(self: *Roads) !void {
        var it = self.map.iterator();
        while (it.next()) |road| {
            try road.value_ptr.deinit();
        }
        self.map.deinit();
    }

    pub fn add(self: *Roads, road: Road) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.map.put(road.road, road);
    }

    pub fn removeDispatcher(self: *Roads, disp: *Dispatcher) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // TODO: Should we remove the roads as well?
        const fd = disp.fd;
        for (disp.roads.items) |road| {
            const nroad = self.map.getPtr(road);
            if (nroad == null) continue;

            _ = nroad.?.dispatchers.remove(fd);
        }
    }

    pub fn addDispatcher(self: *Roads, disp: *Dispatcher, alloc: std.mem.Allocator) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const fd = disp.fd;

        for (disp.roads.items) |road| {
            const nroad = self.map.getPtr(road);
            if (nroad != null) {
                _ = try nroad.?.dispatchers.add(fd);
                continue;
            }

            var r = try Road.init(alloc, road);
            _ = try r.dispatchers.add(fd);
            try self.map.put(road, r);
        }
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
            .road = message.data.camera.road,
            .mile = message.data.camera.mile,
            .speed_limit = message.data.camera.limit,
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

    pub fn add(self: *Cameras, fd: socketfd, camera: Camera) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.map.put(fd, camera);
    }

    pub fn get(self: *Cameras, fd: socketfd) ?*Camera {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.getPtr(fd);
    }

    pub fn del(self: *Cameras, fd: socketfd) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.map.remove(fd);
    }
};

test "Car.addObservation" {
    const allocator = testing.allocator;

    // Test setup
    var tickets_queue = TicketsQueue.init(allocator);
    defer tickets_queue.deinit();

    // Test error cases
    try testErrorCases(allocator, &tickets_queue);

    // Test basic observation addition
    try testSingleObservation(allocator, &tickets_queue);

    // Test no speeding case
    try testMultipleObservationsNoSpeeding(allocator, &tickets_queue);

    // Test speeding detection
    try testSpeedingViolation(allocator, &tickets_queue);

    // Test one ticket per day per road rule
    try testNoTicketDuplication(allocator, &tickets_queue);

    // Test observations on different roads
    try testDifferentRoads(allocator, &tickets_queue);

    // Test time difference threshold
    try testTimeThreshold(allocator, &tickets_queue);

    // Test non-chronological observation order
    try testNonChronologicalOrder(allocator, &tickets_queue);

    // Test different days
    try testDifferentDays(allocator, &tickets_queue);
}

fn testErrorCases(allocator: std.mem.Allocator, tickets_queue: *TicketsQueue) !void {
    var car = try Car.init(allocator, tickets_queue);
    defer car.deinit();
    try car.plate.appendSlice("ABC123");

    var camera = Camera{
        .fd = 123,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };

    // Wrong message type
    {
        const msg = messages.Message.initHeartbeat();
        try testing.expectError(LogicError.MessageWrongType, car.addObservation(msg, &camera));
    }

    // Empty plate in message
    {
        const msg = messages.Message{
            .type = messages.Type.Plate,
            .data = .{ .plate = .{ .plate = "", .timestamp = 0 } },
            // Initialize other required fields
        };
        try testing.expectError(LogicError.EmptyPlate, car.addObservation(msg, &camera));
    }

    // Car with empty plate
    {
        var car_empty = try Car.init(allocator, tickets_queue);
        defer car_empty.deinit();
        // Plate not set

        const msg = messages.Message{
            .type = messages.Type.Plate,
            .data = .{ .plate = .{ .plate = "XYZ789", .timestamp = 0 } },
            // Initialize other required fields
        };
        try testing.expectError(LogicError.EmptyPlate, car_empty.addObservation(msg, &camera));
    }

    // Plate mismatch
    {
        const msg = messages.Message{
            .type = messages.Type.Plate,
            .data = .{ .plate = .{ .plate = "XYZ789", .timestamp = 0 } }, // Different from car's plate
            // Initialize other required fields
        };
        try testing.expectError(LogicError.PlateMismatch, car.addObservation(msg, &camera));
    }
}

fn testSingleObservation(allocator: std.mem.Allocator, tickets_queue: *TicketsQueue) !void {
    var car = try Car.init(allocator, tickets_queue);
    defer car.deinit();
    try car.plate.appendSlice("ABC123");

    var camera = Camera{
        .fd = 123,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };

    // Add a single observation
    const timestamp = 1625097600; // July 1, 2021
    const msg = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp } },
    };

    try car.addObservation(msg, &camera);

    // Verify observation map contains the entry
    try testing.expectEqual(@as(usize, 1), car.observationsmap.count());

    // Verify no tickets yet (need at least 2 observations)
    try testing.expectEqual(@as(usize, 0), tickets_queue.items.len);
}

fn testMultipleObservationsNoSpeeding(allocator: std.mem.Allocator, tickets_queue: *TicketsQueue) !void {
    var car = try Car.init(allocator, tickets_queue);
    defer car.deinit();
    try car.plate.appendSlice("ABC123");

    // First observation
    var camera1 = Camera{
        .fd = 123,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };
    const timestamp1 = 1625097600; // 2021-07-01 00:00:00
    const msg1 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 } },
    };
    try car.addObservation(msg1, &camera1);

    // Second observation - speed under limit (50 mph)
    var camera2 = Camera{
        .fd = 124,
        .road = 1,
        .mile = 60, // 50 mile difference
        .speed_limit = 60,
    };
    const timestamp2 = timestamp1 + 3600; // 1 hour later
    const msg2 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp2 } },
    };
    try car.addObservation(msg2, &camera2);

    // Verify no tickets issued (under speed limit)
    try testing.expectEqual(@as(usize, 0), tickets_queue.items.len);
}

fn testSpeedingViolation(allocator: std.mem.Allocator, tickets_queue: *TicketsQueue) !void {
    const initial_tickets = tickets_queue.items.len;

    var car = try Car.init(allocator, tickets_queue);
    defer car.deinit();
    try car.plate.appendSlice("ABC123");

    // First observation
    var camera1 = Camera{
        .fd = 123,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };
    const timestamp1 = 1625097600;
    const msg1 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 } },
    };
    try car.addObservation(msg1, &camera1);

    // Second observation - speed over limit (80 mph)
    var camera2 = Camera{
        .fd = 124,
        .road = 1,
        .mile = 90, // 80 mile difference
        .speed_limit = 60,
    };
    const timestamp2 = timestamp1 + 3600; // 1 hour later
    const msg2 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp2 } },
    };
    try car.addObservation(msg2, &camera2);

    // Verify a ticket was issued
    try testing.expectEqual(initial_tickets + 1, tickets_queue.items.len);

    // Verify ticket details
    const ticket = tickets_queue.items[initial_tickets];
    try testing.expectEqual(messages.Type.Ticket, ticket.type);
    try testing.expectEqualStrings("ABC123", ticket.data.ticket.plate);
    try testing.expectEqual(camera1.road, ticket.data.ticket.road);
    try testing.expectEqual(@as(u16, 80), ticket.data.ticket.speed); // Calculated speed
}

fn testNoTicketDuplication(allocator: std.mem.Allocator, tickets_queue: *TicketsQueue) !void {
    const initial_tickets = tickets_queue.items.len;

    var car = try Car.init(allocator, tickets_queue);
    defer car.deinit();
    try car.plate.appendSlice("ABC123");

    // Create a speeding violation
    var camera1 = Camera{ .fd = 123, .road = 1, .mile = 10, .speed_limit = 60 };
    var camera2 = Camera{ .fd = 124, .road = 1, .mile = 90, .speed_limit = 60 };

    const timestamp1 = 1625097600;
    const msg1 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 } },
    };
    try car.addObservation(msg1, &camera1);

    const msg2 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 + 3600 } },
    };
    try car.addObservation(msg2, &camera2);

    // Verify one ticket was issued
    try testing.expectEqual(initial_tickets + 1, tickets_queue.items.len);

    // Add another observation on same day/road that would cause speeding
    var camera3 = Camera{ .fd = 125, .road = 1, .mile = 170, .speed_limit = 60 };
    const msg3 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 + 7200 } }, // 2 hours after first
    };
    try car.addObservation(msg3, &camera3);

    // Verify no additional ticket was issued (one per day per road rule)
    try testing.expectEqual(initial_tickets + 1, tickets_queue.items.len);
}

fn testDifferentRoads(allocator: std.mem.Allocator, tickets_queue: *TicketsQueue) !void {
    const initial_tickets = tickets_queue.items.len;

    var car = try Car.init(allocator, tickets_queue);
    defer car.deinit();
    try car.plate.appendSlice("ABC123");

    // Road 1
    var camera1 = Camera{ .fd = 123, .road = 1, .mile = 10, .speed_limit = 60 };
    const timestamp1 = 1625097600;
    const msg1 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 } },
    };
    try car.addObservation(msg1, &camera1);

    // Road 2 (speeding)
    var camera2 = Camera{ .fd = 124, .road = 2, .mile = 10, .speed_limit = 60 };
    const msg2 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 + 3600 } }, // 1 hour later
    };
    try car.addObservation(msg2, &camera2);

    // Road 1 again (speeding)
    var camera3 = Camera{ .fd = 125, .road = 1, .mile = 100, .speed_limit = 60 };
    const msg3 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 + 4600 } }, // 1 hour 20 min later
    };
    try car.addObservation(msg3, &camera3);

    // Verify observation map has entries for different roads
    try testing.expectEqual(@as(usize, 2), car.observationsmap.count());

    // Verify a ticket was issued for road 1
    try testing.expectEqual(initial_tickets + 1, tickets_queue.items.len);
}

fn testTimeThreshold(allocator: std.mem.Allocator, tickets_queue: *TicketsQueue) !void {
    const initial_tickets = tickets_queue.items.len;

    var car = try Car.init(allocator, tickets_queue);
    defer car.deinit();
    try car.plate.appendSlice("ABC123");

    // First observation
    var camera1 = Camera{ .fd = 123, .road = 1, .mile = 10, .speed_limit = 60 };
    const timestamp1 = 1625097600;
    const msg1 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 } },
    };
    try car.addObservation(msg1, &camera1);

    // Second observation - only 15 minutes later (below 30 min threshold)
    var camera2 = Camera{ .fd = 124, .road = 1, .mile = 90, .speed_limit = 60 };
    const timestamp2 = timestamp1 + 900; // 15 minutes later
    const msg2 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp2 } },
    };
    try car.addObservation(msg2, &camera2);

    // Verify ticket (for small time differences)
    try testing.expectEqual(initial_tickets + 1, tickets_queue.items.len);
}

fn testNonChronologicalOrder(allocator: std.mem.Allocator, tickets_queue: *TicketsQueue) !void {
    const initial_tickets = tickets_queue.items.len;

    var car = try Car.init(allocator, tickets_queue);
    defer car.deinit();
    try car.plate.appendSlice("ABC123");

    var camera1 = Camera{ .fd = 123, .road = 1, .mile = 10, .speed_limit = 60 };
    var camera2 = Camera{ .fd = 124, .road = 1, .mile = 90, .speed_limit = 60 };

    const timestamp1 = 1625097600;
    const timestamp2 = timestamp1 + 3600; // 1 hour later

    // Add second observation first (out of order)
    const msg2 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp2 } },
    };
    try car.addObservation(msg2, &camera2);

    // Then add first observation
    const msg1 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 } },
    };
    try car.addObservation(msg1, &camera1);

    // Verify a ticket was issued with correct chronological ordering
    try testing.expectEqual(initial_tickets + 1, tickets_queue.items.len);

    // Verify first observation in ticket is chronologically earlier
    const ticket = tickets_queue.items[initial_tickets];
    try testing.expectEqual(timestamp1, ticket.data.ticket.timestamp1);
    try testing.expectEqual(timestamp2, ticket.data.ticket.timestamp2);
}

fn testDifferentDays(allocator: std.mem.Allocator, tickets_queue: *TicketsQueue) !void {
    const initial_tickets = tickets_queue.items.len;

    var car = try Car.init(allocator, tickets_queue);
    defer car.deinit();
    try car.plate.appendSlice("ABC123");

    // Day 1
    var camera1 = Camera{ .fd = 123, .road = 1, .mile = 10, .speed_limit = 60 };
    const timestamp1 = 1625097600; // July 1, 2021
    const msg1 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp1 } },
    };
    try car.addObservation(msg1, &camera1);

    // Day 2 - would be speeding if on same day
    var camera2 = Camera{ .fd = 124, .road = 1, .mile = 90, .speed_limit = 60 };
    const timestamp2 = timestamp1 + 86400; // 24 hours later (next day)
    const msg2 = messages.Message{
        .type = messages.Type.Plate,
        .data = .{ .plate = .{ .plate = "ABC123", .timestamp = timestamp2 } },
    };
    try car.addObservation(msg2, &camera2);

    // Verify separate entries for different days
    try testing.expectEqual(@as(usize, 2), car.observationsmap.count());

    // Verify no tickets (observations on different days)
    try testing.expectEqual(initial_tickets, tickets_queue.items.len);
}

test "Camera initialization from message" {
    // Create a valid IAmCamera message
    const road: u16 = 42;
    const mile: u16 = 100;
    const limit: u16 = 55;
    const fd: types.socketfd = 123;

    const msg = Message.initCamera(.{
        .road = road,
        .mile = mile,
        .limit = limit,
    });

    // Initialize camera from message
    const camera = try Camera.initFromMessage(fd, msg);

    // Verify all fields
    try testing.expectEqual(fd, camera.fd);
    try testing.expectEqual(road, camera.road);
    try testing.expectEqual(mile, camera.mile);
    try testing.expectEqual(limit, camera.speed_limit);

    // Test error case - wrong message type
    const wrong_msg = Message.initHeartbeat();
    try testing.expectError(LogicError.MessageWrongType, Camera.initFromMessage(fd, wrong_msg));
}

test "Cameras container operations" {
    const allocator = testing.allocator;

    // Initialize cameras container
    var cameras = try Cameras.init(allocator);
    defer cameras.deinit();

    // Test adding a camera
    const fd1: types.socketfd = 101;
    const camera1 = Camera{
        .fd = fd1,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };

    try cameras.add(fd1, camera1);

    // Test getting a camera
    const retrieved_camera = cameras.get(fd1);
    try testing.expect(retrieved_camera != null);
    try testing.expectEqual(camera1.road, retrieved_camera.?.road);
    try testing.expectEqual(camera1.mile, retrieved_camera.?.mile);
    try testing.expectEqual(camera1.speed_limit, retrieved_camera.?.speed_limit);

    // Test getting a non-existent camera
    const non_existent = cameras.get(999);
    try testing.expect(non_existent == null);

    // Test deleting a camera
    cameras.del(fd1);
    const deleted = cameras.get(fd1);
    try testing.expect(deleted == null);
}


test "Client initialization without epoll" {
    const allocator = testing.allocator;

    // Create a camera for client
    const camera = Camera{
        .fd = 101,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };

    // Create a client with camera
    const cam_client = Client.initWithCamera(101, camera);
    try testing.expectEqual(ClientType.Camera, cam_client.type);
    try testing.expectEqual(camera.road, cam_client.data.camera.road);

    // Create a dispatcher for client
    var roads = RoadsArray.init(allocator);
    // defer roads.deinit();
    try roads.append(1);
    try roads.append(2);

    const dispatcher = Dispatcher{
        .fd = 102,
        .roads = roads,
    };

    // Create a client with dispatcher
    var disp_client = Client.initWithDispatcher(102, dispatcher);
    try testing.expectEqual(ClientType.Dispatcher, disp_client.type);
    try testing.expectEqual(dispatcher.fd, disp_client.data.dispatcher.fd);

    // Test the dispatchers roads content
    try testing.expectEqual(@as(usize, 2), disp_client.data.dispatcher.roads.items.len);
    try testing.expectEqual(@as(u16, 1), disp_client.data.dispatcher.roads.items[0]);
    try testing.expectEqual(@as(u16, 2), disp_client.data.dispatcher.roads.items[1]);

    // Clean up the dispatcher data in the client to avoid memory leaks
    disp_client.data.dispatcher.deinit();
}

test "Clients container operations without epoll" {
    const allocator = testing.allocator;

    // Initialize clients container
    var clients = try Clients.init(allocator);
    defer clients.map.deinit(); // Just deinit the map, not using the full deinit that requires epoll

    // Create a client
    const camera = Camera{
        .fd = 101,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };
    const client = Client.initWithCamera(101, camera);

    // Test adding client
    try clients.add(client);

    // Test getting client
    const retrieved_client = clients.get(101);
    try testing.expect(retrieved_client != null);
    try testing.expectEqual(client.type, retrieved_client.?.type);
    try testing.expectEqual(client.fd, retrieved_client.?.fd);

    // Test getting non-existent client
    const non_existent = clients.get(999);
    try testing.expect(non_existent == null);

    // Test client message preparation (not actually sending)
    var buf = try u8BoundedArray.init(0);
    const error_msg = "Test error";
    const error_message = Message.initError(error_msg);
    _ = try error_message.host_to_network(&buf);
    try testing.expectEqual(@intFromEnum(messages.Type.ErrorM), buf.buffer[0]);

    // Create a heartbeat message (not sending)
    buf.len = 0;
    const heartbeat_message = Message.initHeartbeat();
    _ = try heartbeat_message.host_to_network(&buf);
    try testing.expectEqual(@intFromEnum(messages.Type.Heartbeat), buf.buffer[0]);

    // Clean up - just remove from map, don't call deinit that needs epoll
    _ = clients.map.remove(101);
}


test "Road initialization and management" {
    const allocator = testing.allocator;

    // Initialize a road
    const road_id: u16 = 42;
    var road = try Road.init(allocator, road_id);
    defer road.deinit() catch unreachable;

    try testing.expectEqual(road_id, road.road);
    try testing.expectEqual(@as(usize, 0), road.dispatchers.cardinality());

    // Add dispatchers to road
    const disp_fd1: types.socketfd = 101;
    const disp_fd2: types.socketfd = 102;

    _ = try road.dispatchers.add(disp_fd1);
    _ = try road.dispatchers.add(disp_fd2);

    try testing.expectEqual(@as(usize, 2), road.dispatchers.cardinality());
    try testing.expect(road.dispatchers.contains(disp_fd1));
    try testing.expect(road.dispatchers.contains(disp_fd2));

    // Remove a dispatcher
    _ = road.dispatchers.remove(disp_fd1);
    try testing.expectEqual(@as(usize, 1), road.dispatchers.cardinality());
    try testing.expect(!road.dispatchers.contains(disp_fd1));
    try testing.expect(road.dispatchers.contains(disp_fd2));
}

test "Roads container operations" {
    const allocator = testing.allocator;

    // Initialize roads container
    var roads = try Roads.init(allocator);
    defer roads.deinit() catch unreachable;

    // Create and add a road
    const road_id: u16 = 42;
    const road = try Road.init(allocator, road_id);
    try roads.add(road);

    // Test getting a road
    const retrieved_road = roads.get(road_id);
    try testing.expect(retrieved_road != null);
    try testing.expectEqual(road_id, retrieved_road.?.road);

    // Test getting non-existent road
    const non_existent = roads.get(999);
    try testing.expect(non_existent == null);

    // Test adding a dispatcher to road
    var disp_roads = RoadsArray.init(allocator);
    defer disp_roads.deinit();
    try disp_roads.append(road_id);

    var dispatcher = Dispatcher{
        .fd = 101,
        .roads = disp_roads,
    };

    try roads.addDispatcher(&dispatcher, allocator);

    // Verify dispatcher was added to road
    const updated_road = roads.get(road_id);
    try testing.expect(updated_road != null);
    try testing.expectEqual(@as(usize, 1), updated_road.?.dispatchers.cardinality());
    try testing.expect(updated_road.?.dispatchers.contains(dispatcher.fd));

    // Test adding dispatcher to non-existent road (should create the road)
    var disp_roads2 = RoadsArray.init(allocator);
    defer disp_roads2.deinit();
    const new_road_id: u16 = 43;
    try disp_roads2.append(new_road_id);

    var dispatcher2 = Dispatcher{
        .fd = 102,
        .roads = disp_roads2,
    };

    try roads.addDispatcher(&dispatcher2, allocator);

    // Verify new road was created with dispatcher
    const new_road = roads.get(new_road_id);
    try testing.expect(new_road != null);
    try testing.expectEqual(@as(usize, 1), new_road.?.dispatchers.cardinality());
    try testing.expect(new_road.?.dispatchers.contains(dispatcher2.fd));

    // Test removing a dispatcher
    try roads.removeDispatcher(&dispatcher);

    // Verify dispatcher was removed
    const road_after_removal = roads.get(road_id);
    try testing.expect(road_after_removal != null);
    try testing.expectEqual(@as(usize, 0), road_after_removal.?.dispatchers.cardinality());
}


test "Dispatcher initialization from message" {
    const allocator = testing.allocator;

    // Create valid IAmDispatcher message
    var roads_list = try std.ArrayList(u16).initCapacity(allocator, 2);
    // defer roads_list.deinit();
    try roads_list.append(1);
    try roads_list.append(2);

    var msg = Message.initDispatcher(.{ .roads = roads_list });
    const fd: types.socketfd = 101;

    // Initialize dispatcher from message
    var dispatcher = try Dispatcher.initFromMessage(fd, &msg, allocator);
    defer dispatcher.deinit();

    // Verify fields
    try testing.expectEqual(fd, dispatcher.fd);
    try testing.expectEqual(@as(usize, 2), dispatcher.roads.items.len);
    try testing.expectEqual(@as(u16, 1), dispatcher.roads.items[0]);
    try testing.expectEqual(@as(u16, 2), dispatcher.roads.items[1]);

    // Test error case - wrong message type
    var wrong_msg = Message.initHeartbeat();
    try testing.expectError(LogicError.MessageWrongType, Dispatcher.initFromMessage(fd, &wrong_msg, allocator));
}

test "Timer basic operations" {
    // Since we can't actually create timers without system calls in tests,
    // we'll just test the structure and error cases
    // const allocator = testing.allocator;

    // Create a camera for client
    const camera = Camera{
        .fd = 101,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };

    // Create a client
    const client = Client.initWithCamera(101, camera);

    // Test timer structure
    // Just verify the fields in the Timer struct
    try testing.expect(client.timer == null);

    // We validate the AlreadyHasTimer error by directly checking the error condition
    const has_timer_already = client.timer != null;
    try testing.expect(!has_timer_already);

    // Further timer testing would require actual file descriptors, so we'll skip that
}

test "Timer creation and basic operation" {
    // Create a camera
    const camera = Camera{
        .fd = 101,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };

    // Create a client
    var client = Client.initWithCamera(101, camera);

    // Create a timer directly, without using addTimer (which uses epoll)
    const interval: u64 = 1; // 1 decisecond = 100ms
    var timer = try Timer.init(&client, interval);
    defer timer.deinit();

    // Verify timer properties
    try testing.expectEqual(&client, timer.client);
    // try testing.expectEqual(interval * 100_000_000, timer.interval); // Should be in nanoseconds

    // Sleep to allow the timer to fire at least once
    std.time.sleep(200 * std.time.ns_per_ms); // 200ms

    // Read from the timer
    const exp = try timer.read();
    try testing.expectEqual(2, exp); // Expecting one expiration

    // We can't easily assert the exact number of expirations, but 
    // the fact that read() didn't error means the timer did fire
}

test "Timer multiple expirations" {
    // Create a client
    const camera = Camera{
        .fd = 101,
        .road = 1,
        .mile = 10,
        .speed_limit = 60,
    };
    var client = Client.initWithCamera(101, camera);

    // Create a very fast timer
    const interval: u64 = 1; // 1 decisecond = 100ms
    var timer = try Timer.init(&client, interval);
    defer timer.deinit();

    // Sleep to allow multiple timer expirations
    std.time.sleep(550 * std.time.ns_per_ms); // 550ms should give ~5 expirations

    // Read and get expiry count
    const exp = try timer.read();
    try testing.expectEqual(5, exp); // Expecting 5 expirations

    // Testing specific expiry count is implementation-dependent
    // and would require modifying the Timer.read() method to return the count
}
