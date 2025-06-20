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
const Mutex = std.Thread.Mutex;
const allocator = std.heap.page_allocator;
const page_size = 4096;

const FREE_CAPACITY = 0.5; // Percentage

pub const Queue = struct {
    data: []u8,
    capacity: u64,
    size: u64,

    pub fn init() !Queue {
        const data = try allocator.alloc(u8, page_size);
        return Queue{
            .data = data,
            .capacity = page_size,
            .size = 0,
        };
    }

    pub fn deinit(self: *Queue) void {
        allocator.free(self.data);
    }

    fn expand_capacity(self: *Queue, newsize: u64) !void {
        if (newsize == 0) return;

        self.size += newsize;
        var expand = false;
        while (true) {
            const fill = @as(f64, @floatFromInt(self.size / self.capacity));
            if (fill <= FREE_CAPACITY) break;

            expand = true;
            self.capacity *= 2;
        }
        if (!expand) return;

        const ndata = try allocator.realloc(self.data, self.capacity);
        self.data = ndata;
    }

    pub fn push(self: *Queue, data: []const u8) !void {
        if (data.len == 0) return;

        const os = self.size;
        try self.expand_capacity(data.len);
        @memcpy(self.data[os .. os + data.len], data);
    }

    pub fn push_ex(self: *Queue, size: u64) !void {
        if (size == 0) return;

        try self.expand_capacity(size);
    }

    pub fn get_writable_data(self: Queue) []u8 {
        return self.data[self.size..];
    }

    pub fn pop(self: *Queue) []const u8 {
        if (self.size == 0) return &[_]u8{};

        const r = self.data[0..self.size];
        self.size = 0;
        return r;
    }

    pub fn peek(self: Queue) []const u8 {
        return self.data[0..self.size];
    }
};

// Tests
test "Queue initialization and deinitialization" {
    var queue = try Queue.init();
    defer queue.deinit();

    try testing.expectEqual(@as(u64, 0), queue.size);
}

test "Queue push and pop" {
    var queue = try Queue.init();
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
    var queue = try Queue.init();
    defer queue.deinit();

    const data = "This is a longer string that will cause expansion";
    try queue.push(data);

    try testing.expect(queue.capacity > 16);
    try testing.expectEqual(data.len, queue.size);
    try testing.expectEqualSlices(u8, data, queue.peek());
}

test "Queue push_ex and get_writable_data" {
    var queue = try Queue.init();
    defer queue.deinit();

    {
        const writable = queue.get_writable_data();
        @memcpy(writable[0..10], "0123456789");
        try queue.push_ex(10);
    }
    const writable = queue.get_writable_data();
    try testing.expectEqual(@as(usize, 4096 - 10), writable.len);
    try testing.expectEqualSlices(u8, "0123456789", queue.peek());
}

test "Queue multiple pushes" {
    var queue = try Queue.init();
    defer queue.deinit();

    try queue.push("First");
    try queue.push(" ");
    try queue.push("Second");

    try testing.expectEqualSlices(u8, "First Second", queue.peek());
}

test "Queue empty pop" {
    var queue = try Queue.init();
    defer queue.deinit();

    const empty = queue.pop();
    try testing.expectEqualSlices(u8, &[_]u8{}, empty);
}
