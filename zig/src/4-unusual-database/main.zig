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
    _ = try std.net.Address.parseIp(name, port);
    const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP);
    defer std.posix.close(sock);

    var db = try Database.init(allocator);
    var buff: [1024]u8 = undefined;

    var sa: std.net.Address = undefined;
    const sl: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    var sl_copy = sl;
    while (true) {
        @memset(@as([*]u8, @ptrCast(&sa))[0..@sizeOf(std.net.Address)], 0);
        sl_copy = sl;
        const result = std.posix.recvfrom(sock, &buff, 0, &sa.any, &sl_copy) catch |err| {
            debug("ERROR: recvfrom failed: {!}\n", .{err});
            return err;
        };

        if (result == 0) continue;

        const resp = buff[0..result];
        const eqidx = std.mem.indexOf(u8, resp, "=");
        if (eqidx) |idx| {
            // TODO: Insert request
            const key = resp[0..idx];
            const value = resp[idx..];
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

            _ = value;
            // if (value) |val| {
            //     // TODO: format response '{s}={s}', .{resp, value}
            //     // TODO: Use this to respond
            //     // _ = posix.sendto(fd, queries[i], posix.MSG.NOSIGNAL, &ns[j].any, sl) catch undefined;
            // }
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
