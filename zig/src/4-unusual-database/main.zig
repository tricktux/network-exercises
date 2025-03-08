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

const DatabaseError = error{
    AttemptedToInsertReservedKey,
    KeyLengthExceeded,
    ValueLengthExceeded,
};

const max_key_length: usize = 1024;

const Database = struct {
    const Self = @This();

    comptime version_key: []const u8 = "version",
    comptime version_value: []const u8 = "ReinaldoKeyValueStore1.0",
    comptime empty: []const u8 = "ReinaldoMolina204355E=2G5x~uVlHie=C",

    store: std.StringArrayHashMap([]const u8) = undefined,

    pub fn init(allocator: std.mem.Allocator) !Database {
        var r = Database{
            .store = std.StringArrayHashMap([]const u8).init(allocator),
        };
        try r.store.put(r.version_key, r.version_value);
        return r;
    }

    pub fn deinit(self: *Database) void {
        self.store.deinit();
    }

    pub fn insert(self: *Database, key: []const u8, value: []const u8) !void {
        if (key.len > max_key_length) return DatabaseError.KeyLengthExceeded;
        if (value.len > max_key_length) return DatabaseError.ValueLengthExceeded;
        if (std.mem.eql(u8, key, self.version_key)) return DatabaseError.AttemptedToInsertReservedKey;

        const k = if (key.len == 0) self.empty else key;
        const v = if (value.len == 0) self.empty else value;

        try self.store.put(k, v);
    }

    pub fn retrieve(self: *Database, key: []const u8) !?[]const u8 {
        if (key.len > max_key_length) return DatabaseError.KeyLengthExceeded;

        const k = if (key.len == 0) self.empty else key;
        const r = self.store.get(k);
        if (r == null) return null;

        if (std.mem.eql(u8, r.?, self.empty)) return "";
        return r;
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

test "StringArrayHashMap" {
    const allocator = std.testing.allocator;
    var map = std.StringArrayHashMap([]const u8).init(allocator);
    defer map.deinit();
    try map.put("key1", "value1");
    try map.put("key2", "value2");
    const value1 = map.get("key1");
    try testing.expectEqualStrings("value1", value1.?);
    const value2 = map.get("key2");
    try testing.expectEqualStrings("value2", value2.?);
}

test "Database - initialization and version" {
    const allocator = std.testing.allocator;
    var db = try Database.init(allocator);
    defer db.deinit();

    const version = try db.retrieve("version");
    try testing.expectEqualStrings("ReinaldoKeyValueStore1.0", version.?);
}

test "Database - insert and retrieve" {
    const allocator = std.testing.allocator;
    var db = try Database.init(allocator);
    defer db.deinit();

    try db.insert("key1", "value1");
    try db.insert("key2", "value2");

    const value1 = try db.retrieve("key1");
    try testing.expectEqualStrings("value1", value1.?);

    const value2 = try db.retrieve("key2");
    try testing.expectEqualStrings("value2", value2.?);
}

test "Database - empty key and value" {
    const allocator = std.testing.allocator;
    var db = try Database.init(allocator);
    defer db.deinit();

    try db.insert("", "emptykey");
    try db.insert("emptyvalue", "");

    const emptyKeyValue = try db.retrieve("");
    try testing.expectEqualStrings("emptykey", emptyKeyValue.?);

    const emptyValue = try db.retrieve("emptyvalue");
    try testing.expectEqualStrings("", emptyValue.?);
}

test "Database - overwrite value" {
    const allocator = std.testing.allocator;
    var db = try Database.init(allocator);
    defer db.deinit();

    try db.insert("key", "value1");
    try db.insert("key", "value2");

    const value = try db.retrieve("key");
    try testing.expectEqualStrings("value2", value.?);
}

test "Database - retrieve non-existent key" {
    const allocator = std.testing.allocator;
    var db = try Database.init(allocator);
    defer db.deinit();

    const value = try db.retrieve("nonexistent");
    try testing.expect(value == null);
}

test "Database - insert reserved key" {
    const allocator = std.testing.allocator;
    var db = try Database.init(allocator);
    defer db.deinit();

    const result = db.insert("version", "newversion");
    try testing.expectError(error.AttemptedToInsertReservedKey, result);
}
