const std = @import("std");
const linux = std.os.linux;
const debug = std.debug.print;
const testing = std.testing;
const fmt = std.fmt;
const time = std.time;
const Thread = std.Thread;
const u8fifo = std.fifo.LinearFifo(u8, .Dynamic);

// Constants
const name: []const u8 = "0.0.0.0";
const port = 18888;
const needle = "\n";

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Create server
    var server: std.net.Server = undefined;
    defer server.deinit();
    {
        const addrlist = try std.net.getAddressList(allocator, name, port);
        defer addrlist.deinit();
        debug("Got Addresses: '{s}'!!!\n", .{addrlist.canon_name.?});

        for (addrlist.addrs) |addr| {
            debug("\tTrying to listen...\n", .{});
            // Not intuitive but `listen` calls `socket, bind, and listen`
            server = addr.listen(.{}) catch continue;
            debug("\tGot one!\n", .{});
            break;
        }
    }

    // Initialize thread pool
    const cpus = try std.Thread.getCpuCount();
    var tp: std.Thread.Pool = undefined;
    try tp.init(.{ .allocator = allocator, .n_jobs = @as(u32, @intCast(cpus)) });
    defer tp.deinit();

    debug("ThreadPool initialized with {} capacity\n", .{cpus});
    debug("We are listeninig baby!!!...\n", .{});
    const thread_id = std.Thread.getCurrentId();
    while (true) {
        debug("INFO({d}): waiting for a new connection...\n", .{thread_id});
        const connection = try server.accept();
        debug("INFO({d}): got new connection!!!\n", .{thread_id});
        try tp.spawn(handle_connection, .{ connection, allocator });
    }
}

const Database = struct {
    store: std.StringArrayHashMap([]const u8) = undefined,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) Database {
        const r = Database{ .store = std.StringArrayHashMap([]const u8).init(allocator) };
        // TODO: insert version here
        return r;
    }

    pub fn deinit(self: *Database) void {
        self.store.deinit();
    }

    pub fn insert(self: *Database, key: []const u8, value: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.store.put(key, value);
    }

    pub fn retrieve(self: *Database, key: []const u8) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.store.get(key);
    }

};

fn handle_connection(connection: std.net.Server.Connection, alloc: std.mem.Allocator) void {
    const thread_id = std.Thread.getCurrentId();

    const stream = connection.stream;
    defer stream.close();

    var recv_fifo = std.fifo.LinearFifo(u8, .Dynamic).init(alloc);
    defer recv_fifo.deinit();

    stream.writeAll("Welcome to budgetchat! What shall I call you?\n") catch |err| {
        debug("\t\tERROR({d}): error sendAll function {!}... closing this connection\n", .{ thread_id, err });
        return;
    };

    var msg_buffer = std.BoundedArray(u8, 1024).init(0) catch |err| {
        debug("\tERROR({d}): error while initializing msg_buffer: {!}\n", .{ thread_id, err });
        return;
    };

    while (true) {
        debug("\tINFO({d}): waiting for some data...\n", .{thread_id});
        const data = recv_fifo.writableWithSize(std.mem.page_size * 4) catch |err| {
            debug("\tERROR({d}): error while recv_fifo.writableWithSize: {!}\n", .{ thread_id, err });
            return;
        };

        const bytes = stream.read(data) catch |err| {
            debug("\tERROR({d}): error {!}... closing this connection\n", .{ thread_id, err });
            return;
        };
        if (bytes == 0) {
            debug("\t\tWARN({d}): Client closing this connection\n", .{
                thread_id,
            });
            return;
        }

        recv_fifo.update(bytes);

        // Check if we have a full message
        const datapeek = recv_fifo.readableSlice(0);
        // TODO: Maybe switch to using readUntilDelimiterOrEnd
        // Danger here of sending out more than one message
        const idx = std.mem.lastIndexOf(u8, datapeek, needle);
        if (idx == null) continue;

        // Clean up
        defer recv_fifo.discard(recv_fifo.readableLength());
        defer msg_buffer.clear();

        // const msg = datapeek[0..idx.?];
    }
}
