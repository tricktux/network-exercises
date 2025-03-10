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
const needle = "=";

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Create server
    const addr = try std.net.Address.parseIp(name, port);
    const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP);
    defer std.posix.close(sock);

    std.posix.bind(sock, &addr.any, addr.getOsSockLen()) catch |err| {
        debug("ERROR: bind failed: {!}\n", .{err});
        return err;
    };

    var db = try Database.init(allocator);
    var buff: [1024]u8 = undefined;

    var msg_buffer = std.BoundedArray(u8, 1024).init(0) catch |err| {
        debug("ERROR: error while initializing msg_buffer: {!}\n", .{ err });
        return;
    };

    var sa: std.net.Address = undefined;
    const sl: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    var sl_copy = sl;
    while (true) {
        @memset(@as([*]u8, @ptrCast(&sa))[0..@sizeOf(std.net.Address)], 0);
        sl_copy = sl;
        debug("INFO: waiting for request\n", .{});
        const result = std.posix.recvfrom(sock, &buff, 0, &sa.any, &sl_copy) catch |err| {
            debug("ERROR: recvfrom failed: {!}\n", .{err});
            return err;
        };

        if (result == 0) continue;

        const resp = buff[0..result];
        const eqidx = std.mem.indexOf(u8, resp, needle);
        if (eqidx) |idx| {
            // TODO: Insert request
            const key = resp[0..idx];
            const value = resp[idx + 1..];
            debug("INFO: inserting key: '{s}', value: '{s}'\n", .{key, value});
            db.insert(key, value) catch |err| {
                debug("ERROR: inserting key: '{s}', value: '{s}', error: {!}\n", .{key, value, err});
                continue;
            };
        } else {
            // TODO: Retrieve request
            const value = db.retrieve(resp) catch |err| {
                debug("ERROR: retrieving key: '{s}', error: {!}\n", .{resp, err});
                continue;
            };

            if (value) |val| {
                // TODO: format response '{s}={s}', .{resp, value}
                debug("INFO: retrieving key: '{s}', value: '{s}'\n", .{resp, val});
                std.fmt.format(msg_buffer.writer().any(), "{s}={s}", .{resp, val}) catch |err| {
                    debug("ERROR: formatting response: '{s}={s}', error: {!}\n", .{resp, val, err});
                    continue;
                };
                // TODO: Use this to respond
                _ = std.posix.sendto(sock, msg_buffer.constSlice(), 0, &sa.any, sl) catch |err| {
                    debug("ERROR: sendto failed: {!}\n", .{err});
                    return err;
                };
            }
        }

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

test "UDP client-server interaction" {
    // Start the server in a separate thread
    const server_thread = try std.Thread.spawn(.{}, main, .{});
    defer server_thread.join();

    // Give the server some time to start
    time.sleep(time.ns_per_s / 10);
    // const sl: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);

    // Create a UDP client
    var server_addr = try std.net.Address.parseIp(name, port);
    const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP);
    defer std.posix.close(sock);

    // Test inserting a key-value pair
    _ = std.posix.sendto(sock, "test_key=test_value", 0, &server_addr.any, server_addr.getOsSockLen()) catch unreachable;

    // Test retrieving the value
    // try client.send("test_key");
    var recv_buf: [1024]u8 = undefined;
    // var recv_buf = std.BoundedArray(u8, 1024).init(1024) catch unreachable;
    var sl_copy = server_addr.getOsSockLen();
    _ = std.posix.sendto(sock, "test_key", 0, &server_addr.any, server_addr.getOsSockLen()) catch unreachable;
    const recvnum = try std.posix.recvfrom(sock, &recv_buf, 0, &server_addr.any, &sl_copy);
    debug("TEST: testing test_key\n", .{});
    // recv_buf.append('\0') catch unreachable;
    // const response = recv_buf.constSlice();
    try testing.expectEqualStrings("test_key=test_value", recv_buf[0..recvnum]);

    // Test inserting and retrieving an empty value
    debug("TEST: inserting empty value\n", .{});
    _ = std.posix.sendto(sock, "empty_value=", 0, &server_addr.any, server_addr.getOsSockLen()) catch unreachable;
    _ = std.posix.sendto(sock, "empty_value", 0, &server_addr.any, server_addr.getOsSockLen()) catch unreachable;
    var recv_buf2: [1024]u8 = undefined;
    const recvnum2 = std.posix.recvfrom(sock, &recv_buf2, 0, &server_addr.any, &sl_copy) catch unreachable;
    // const empty_response = recv_buf.constSlice();
    try testing.expectEqualStrings("empty_value=", recv_buf2[0..recvnum2]);


    // // Test retrieving a non-existent key
    // try client.send("non_existent_key");
    // const non_existent_bytes_received = try client.receive(&recv_buf);
    // try testing.expect(non_existent_bytes_received == 0);
}

