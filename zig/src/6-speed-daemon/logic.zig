const std = @import("std");
const Message = @import("messages.zig").Message;
const messages = @import("messages.zig");
const linux = std.os.linux;

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

// TODO: on main create a context with all the data
const Context = struct {
    cars: *Cars,
    roads: *Roads,
    cameras: *Cameras,
    tickets: *Tickets,
    clients: *Clients,
};

// TODO: Client
// - timer = underfined
// - OnWantHeartbeat
//  - timer = Timer.init
// - OnDeinit
//  - timer.deinit
// TODO: Timer
// - timerfd
// - &client
// - interval
// TODO: Timers
// - TimerHashMap = std.AutoHashMap(socketfd, Timer)
// - Add function adds to epoll
// - Remove function removes to epoll

const ClientType = enum {
    Camera,
    Dispatcher,
};

const EpollManager = struct {
    epollfd: socketfd,
    event_flags: comptime_int = linux.EPOLL.IN | linux.EPOLL.ET,
    // TODO: is `epoll_ctl` thread safe? Is this needed?
    mutex: std.Thread.Mutex = .{},
    ready_events: EpollEventsArray,

    pub fn init() !EpollManager {
        const epollfd = try std.posix.epoll_create1(0);
        return EpollManager{
            .epollfd = epollfd,
            .ready_events = EpollEventsArray.init(0),
        };
    }

    pub fn deinit(self: *EpollManager) void {
        _ = std.posix.close(self.epollfd);
    }

    pub fn add(self: *EpollManager, fd: socketfd) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const event = std.posix.epoll_event{
            .events = self.event_flags,
            .data = .{ .fd = fd },
        };

        try std.posix.epoll_ctl(self.epollfd, std.posix.EPOLL_CTL_ADD, fd, &event);
    }

    pub fn remove(self: *EpollManager, fd: socketfd) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try std.posix.epoll_ctl(self.epollfd, std.posix.EPOLL_CTL_DEL, fd, null);
    }

    // TODO: Add wait function that returns &ready_events
    // TODO: Takes in a timeout value
};

const Clients = struct {
    map: ClientHashMap,
    mutex: std.Thread.Mutex = .{},

    pub fn init(alloc: std.mem.Allocator) !Clients {
        return Clients{
            .map = ClientHashMap.init(alloc),
        };
    }

    pub fn deinit(self: *Clients) void {
        // TODO: iterate deinit clients
        const it = self.map.iterator();
        for (it.next()) |client| {
            client.deinit();
        }

        self.map.deinit();
    }

    pub fn add(self: *Clients, client: Client) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.map.put(client.fd, client);
    }

    pub fn get(self: *Clients, fd: socketfd) ?Client {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.get(fd);
    }

    pub fn remove(self: *Clients, fd: socketfd) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.map.remove(fd);
        // TODO: call deinit
    }
};

const Client = struct {
    fd: socketfd,
    type: ClientType,
    wantshearbaecon: bool = false,
    data: union {
        camera: Camera,
        dispatcher: Dispatcher,
    },

    pub fn initWithCamera(fd: socketfd, message: Message) !Client {
        if (message.type != messages.Type.IAmCamera) return LogicError.MessageWrongType;
        return Client{
            .fd = fd,
            .type = ClientType.Camera,
            .data = .{ .camera = Camera.initFromMessage(fd, message) },
        };
    }

    pub fn initWithDispatcher(fd: socketfd, message: Message) !Client {
        if (message.type != messages.Type.IAmDispatcher) return LogicError.MessageWrongType;
        return Client{
            .fd = fd,
            .type = ClientType.Dispatcher,
            .data = .{ .dispatcher = Dispatcher.initFromMessage(fd, message) },
        };
    }

    pub fn deinit(self: *Client) void {
        _ = std.posix.close(self.fd);
        switch (self.data) {
            .dispatcher => self.data.dispatcher.deinit(),
            else => {},
        }
    }
};

const Dispatcher = struct {
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

const Ticket = struct {
    dispatched: bool = false,
    ticket: Message,
};

const Car = struct {
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

const LogicError = error{
    EmptyPlate,
    MessageWrongType,
};

const Cars = struct {
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

    pub fn get(self: *Cars, plate: []const u8) ?Car {
        if (plate.len == 0) return LogicError.EmptyPlate;

        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.get(plate);
    }

    pub fn remove(self: *Cars, plate: []const u8) void {
        if (plate.len == 0) return LogicError.EmptyPlate;

        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.map.remove(plate);
    }
};

const Road = struct {
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
};

const Roads = struct {
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

    pub fn add(self: *Roads, road: Road) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.map.put(road.road, road);
    }

    pub fn get(self: *Roads, road: u16) ?Road {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.get(road);
    }

    pub fn remove(self: *Roads, road: u16) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.map.remove(road);
    }
};

const Camera = struct {
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

const Cameras = struct {
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

    pub fn get(self: *Cameras, fd: socketfd) ?Camera {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.get(fd);
    }

    pub fn remove(self: *Cameras, fd: socketfd) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.map.remove(fd);
    }
};
