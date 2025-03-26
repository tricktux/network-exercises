const std = @import("std");

const socketfd = std.posix.socket_t;
const CameraHashMap = std.AutoHashMap(std.posix.socket_t, Camera);
const RoadHashMap = std.AutoHashMap(u16, Road);
const ArrayCameraId = std.ArrayList(socketfd);

const Road = struct {
    road: u16,
    speed_limit: ?u16 = null,
    dispatcher: ?socketfd = null, // Dispatcher associated with this road
    cameras: ArrayCameraId, // Cameras associated with this road

    pub fn init(alloc: std.mem.Allocator) !Road {
        return Road{
            .cameras = ArrayCameraId.init(alloc),
        };
    }

    pub fn deinit(self: *Road) void {
        self.cameras.deinit();
    }

    pub fn add_camera(self: *Road, camera: socketfd) !void {
        try self.cameras.append(camera);
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
