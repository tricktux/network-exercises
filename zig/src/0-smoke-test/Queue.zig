//! This is a special Queue, geared towards network sockets, performance, and 
//! self managing memory
/// The queue will on write:
/// - Expand the queue's capacity until the following:
///   - The current size of the queue + the size of the new data
///   will not fill the capacity more than FREE_CAPACITY %
///   - The expansion will be in powers of 2
/// - The queue's free_capacity is used to `recv` from the sockets
/// - Hence we need to quarantee that there will be enough capacity to
/// receive, otherwise will impact performance

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const FREE_CAPACITY = 0.5; // Percentage
const Self = @This();

data: []u8,
capacity: u64,
size: u64,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, capacity: u64) !Self {
    const data = try allocator.alloc(u8, capacity);
    return Self{
        .data = data,
        .capacity = capacity,
        .size = 0,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.data);
}

fn expand_capacity(self: *Self, newsize: u64) !void {
    if (newsize == 0) return;

    self.size += newsize;
    var expand = false;
    while (true) {
        const newfree = self.capacity - self.size;
        const fill = @as(f64, @floatFromInt(if (newfree < 0) 0 else newfree / self.capacity));
        if (fill > FREE_CAPACITY) break;

        expand = true;
        self.capacity *= 2;
    }
    if (!expand) return;

    const ndata = try self.allocator.realloc(self.data, self.capacity);
    self.data = ndata;
}

pub fn push(self: *Self, data: []const u8) !void {
    if (data.len == 0) return;

    const os = self.size;
    try self.expand_capacity(data.len);
    @memcpy(self.data[os..data.len], data);
}

pub fn push_ex(self: *Self, size: u64) !void {
    if (size == 0) return;

    try self.expand_capacity(size);
}

pub fn get_writable_data(self: Self) []u8 {
    return self.data[self.size..];
}

pub fn pop(self: *Self) []const u8 {
    if (self.size == 0) return &[_]u8{};

    const r = self.data[0..self.size];
    self.size = 0;
    return r;
}

pub fn peek(self: Self) []const u8 {
    return self.data[0..self.size];
}


// Tests
const Queue = @This();
test "Queue initialization and deinitialization" {
    var queue = try Queue.init(testing.allocator, 64);
    defer queue.deinit();

    try testing.expectEqual(@as(u64, 64), queue.capacity);
    try testing.expectEqual(@as(u64, 0), queue.size);
}

test "Queue push and pop" {
    var queue = try Queue.init(testing.allocator, 64);
    defer queue.deinit();

    const data = "Hello, World!";
    try queue.push(data);

    try testing.expectEqual(@as(u64, data.len), queue.size);
    try testing.expectEqualSlices(u8, data, queue.peek());

    const popped = queue.pop();
    try testing.expectEqualSlices(u8, data, popped);
    try testing.expectEqual(@as(u64, 0), queue.size);
}

test "Queue capacity expansion" {
    var queue = try Queue.init(testing.allocator, 16);
    defer queue.deinit();

    const data = "This is a longer string that will cause expansion";
    try queue.push(data);

    try testing.expect(queue.capacity > 16);
    try testing.expectEqual(data.len, queue.size);
    try testing.expectEqualSlices(u8, data, queue.peek());
}

test "Queue push_ex and get_writable_data" {
    var queue = try Queue.init(testing.allocator, 64);
    defer queue.deinit();

    try queue.push_ex(10);
    const writable = queue.get_writable_data();
    try testing.expectEqual(@as(usize, 10), writable.len);

    @memcpy(writable, "0123456789");
    try testing.expectEqualSlices(u8, "0123456789", queue.peek());
}

test "Queue multiple pushes" {
    var queue = try Queue.init(testing.allocator, 64);
    defer queue.deinit();

    try queue.push("First");
    try queue.push(" ");
    try queue.push("Second");

    try testing.expectEqualSlices(u8, "First Second", queue.peek());
}

test "Queue empty pop" {
    var queue = try Queue.init(testing.allocator, 64);
    defer queue.deinit();

    const empty = queue.pop();
    try testing.expectEqualSlices(u8, &[_]u8{}, empty);
}
