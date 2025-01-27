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

const FREE_CAPACITY = 0.5; // Percentage

pub const Queue = struct {
    data: []u8,
    capacity: u64,
    size: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: u64) !Queue {
        const data = try allocator.alloc(u8, capacity);
        return Queue{
            .data = data,
            .capacity = capacity,
            .size = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Queue) void {
        self.allocator.free(self.data);
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

        const ndata = try self.allocator.realloc(self.data, self.capacity);
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

pub const Pool = struct {
    queues: std.ArrayList(Queue),
    available: std.ArrayList(usize),
    allocator: std.mem.Allocator,
    mutex: Mutex,
    queue_capacity: u64,

    pub fn init(allocator: std.mem.Allocator, initial_queues: usize, queue_capacity: u64) !Pool {
        var queues = std.ArrayList(Queue).init(allocator);
        errdefer queues.deinit();

        var available = std.ArrayList(usize).init(allocator);
        errdefer available.deinit();

        try queues.ensureTotalCapacity(initial_queues);
        try available.ensureTotalCapacity(initial_queues);

        for (0..initial_queues) |i| {
            const queue = try Queue.init(allocator, queue_capacity);
            try queues.append(queue);
            try available.append(i);
        }

        return Pool{
            .queues = queues,
            .available = available,
            .allocator = allocator,
            .mutex = .{},
            .queue_capacity = queue_capacity,
        };
    }

    pub fn deinit(self: *Pool) void {
        for (self.queues.items) |*queue| {
            queue.deinit();
        }
        self.queues.deinit();
        self.available.deinit();
    }

    pub fn get_queue(self: *Pool) !*Queue {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.available.popOrNull()) |index| {
            return &self.queues.items[index];
        }

        // Allocate a new queue
        const new_queue = try Queue.init(self.allocator, self.queue_capacity);
        try self.queues.append(new_queue);
        return &self.queues.items[self.queues.items.len - 1];
    }

    pub fn return_queue(self: *Pool, queue: *Queue) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const queptr = @intFromPtr(queue);
        const myqueptr = @intFromPtr(self.queues.items.ptr);
        if (queptr < myqueptr) {
            std.debug.print("[pool.return_queue]: ERROR: invalid queptr!\n", .{});
            return;
        }
        if (queptr == myqueptr) {
            try self.available.append(0);
            return;
        }
        const index = queptr - myqueptr;
        const queue_index = @divExact(index, @sizeOf(Queue));
        try self.available.append(queue_index);
    }
};

// Updated test cases
test "Queue.Pool initialization and deinitialization" {
    var pool = try Pool.init(testing.allocator, 5, 64);
    defer pool.deinit();

    try testing.expectEqual(@as(usize, 5), pool.queues.items.len);
    try testing.expectEqual(@as(usize, 5), pool.available.items.len);
}

test "Queue.Pool get_queue and return_queue with dynamic allocation" {
    var pool = try Pool.init(testing.allocator, 3, 64);
    defer pool.deinit();

    const queue1 = try pool.get_queue();
    const queue2 = try pool.get_queue();
    const queue3 = try pool.get_queue();

    try testing.expectEqual(@as(usize, 0), pool.available.items.len);

    // This should allocate a new queue
    const queue4 = try pool.get_queue();
    try testing.expectEqual(@as(usize, 4), pool.queues.items.len);

    try pool.return_queue(queue2);
    try testing.expectEqual(@as(usize, 1), pool.available.items.len);

    const queue5 = try pool.get_queue();
    try testing.expectEqual(queue2, queue5);

    try pool.return_queue(queue1);
    try pool.return_queue(queue3);
    try pool.return_queue(queue4);
    try pool.return_queue(queue5);

    try testing.expectEqual(@as(usize, 4), pool.available.items.len);
}

test "Queue.Pool thread safety" {
    const ThreadContext = struct {
        pool: *Pool,
        iterations: usize,
    };

    const thread_fn = struct {
        fn func(ctx: *ThreadContext) !void {
            var i: usize = 0;
            while (i < ctx.iterations) : (i += 1) {
                const queue = try ctx.pool.get_queue();
                try queue.push("test");
                _ = queue.pop();
                try ctx.pool.return_queue(queue);
            }
        }
    }.func;

    var pool = try Pool.init(testing.allocator, 5, 64);
    defer pool.deinit();

    const num_threads = 10;
    const iterations_per_thread = 1000;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    for (&threads, &contexts) |*thread, *ctx| {
        ctx.* = .{ .pool = &pool, .iterations = iterations_per_thread };
        thread.* = try std.Thread.spawn(.{}, thread_fn, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    try testing.expectEqual(@as(usize, 10), pool.available.items.len);
    try testing.expect(pool.queues.items.len >= 5);
}

// Tests
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

    const writable = queue.get_writable_data();
    @memcpy(writable[0..10], "0123456789");
    try queue.push_ex(10);
    try testing.expectEqual(@as(usize, 64), writable.len);
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
