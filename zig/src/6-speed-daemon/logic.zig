const std = @import("std");
const messages = @import("messages.zig");
const types = @import("types.zig");
const linux = std.os.linux;

const u8BoundedArray = types.u8BoundedArray;
const Message = messages.Message;
const socketfd = std.posix.socket_t;
const CameraHashMap = std.AutoHashMap(std.posix.socket_t, Camera);
const RoadHashMap = std.AutoHashMap(u16, Road);
const ArrayCameraId = std.ArrayList(socketfd);
const String = std.ArrayList(u8);
const Tickets = std.ArrayList(Ticket);
const Observations = std.ArrayList(Message);
const CarHashMap = std.StringHashMap(Car);
const ClientHashMap = std.AutoHashMap(socketfd, Client);
const EpollEventsArray = std.BoundedArray(linux.epoll_event, 256);
const TimerHashMap = std.AutoHashMap(socketfd, Timer);

// TODO: on main create a context with all the data
pub const Context = struct {
    cars: *Cars,
    roads: *Roads,
    cameras: *Cameras,
    tickets: *Tickets,
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
        const event = std.posix.epoll_event{
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

    pub fn deinit(self: *Clients, epoll: *EpollManager) void {
        const it = self.map.iterator();
        for (it.next()) |client| {
            client.deinit(epoll);
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
    data: union {
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

    pub fn deinit(self: *Client, epoll: *EpollManager) void {
        if (self.timer != null) {
            epoll.del(self.timer.?.fd);
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

pub const Ticket = struct {
    dispatched: bool = false,
    ticket: Message,
};

pub const Car = struct {
    plate: String,
    tickets: Tickets,
    observations: Observations,

    pub fn init(alloc: std.mem.Allocator) !Car {
        return Car{
            .plate = String.initCapacity(alloc, 32),
            .tickets = Tickets.initCapacity(alloc, 4),
            .observations = Observations.initCapacity(alloc, 8),
        };
    }

    pub fn deinit(self: *Car) void {
        self.plate.deinit();
        self.tickets.deinit();
        self.observations.deinit();
    }
};

pub const LogicError = error{
    EmptyPlate,
    MessageWrongType,
    AlreadyHasTimer,
};

pub const Cars = struct {
    map: CarHashMap,
    mutex: std.Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !Cars {
        return Cars{
            .map = CarHashMap.init(alloc),
            .allocator = alloc,
        };
    }

    pub fn deinit(self: *Cars) void {
        const it = self.map.iterator();

        while (it.next()) |car| {
            car.deinit();
        }

        self.map.deinit();
    }

    pub fn add(self: *Cars, plate: []const u8) !void {
        if (plate.len == 0) return LogicError.EmptyPlate;

        self.mutex.lock();
        defer self.mutex.unlock();

        var car = try Car.init(self.allocator);
        car.plate.appendSlice(plate);
        try self.map.put(car.plate.toOwnedArray(), car);
    }

    pub fn get(self: *Cars, plate: []const u8) ?*Car {
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
