//! This is a special Queue, geared towards network sockets, performance, and auto filling

// Yeah, this is a special case that resizes itself
// - [ ] how are the allocators used?

const std = @import("std");
const assert = std.debug.assert;

const FREE_CAPACITY = 0.5; // Percentage
const Self = @This();

data: []u8,
head: []u8,
capacity: u64,
size: u64,
free_capacity: u64,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, capacity: u64) !Self {
    const data = try allocator.alloc(u8, capacity);
    return Self{
        .data = data,
        .head = data,
        .capacity = capacity,
        .size = 0,
        .free_capacity = capacity,
        .allocator = allocator,
    };
}

/// This function will:
/// - Expand the queue's capacity until the following:
///   - The current size of the queue + the size of the new data
///   will not fill the capacity more than FREE_CAPACITY %
///   - The expansion will be in powers of 2
/// - The queue's free_capacity is used to `recv` from the sockets
/// - Hence we need to quarantee that there will be enough capacity to
/// receive, otherwise will impact performance
fn expand_capacity(self: *Self, newsize: u64) !void {
    if (newsize == 0) return;

    self.size += newsize;
    self.free_capacity -= self.size;
    var expand = false;
    while ((self.free_capacity / self.capacity) > FREE_CAPACITY) {
        expand = true;
        self.capacity *= 2;
        self.free_capacity = self.capacity - self.size;
    }
    if (!expand) return;

    const ndata = try self.allocator.realloc(self.data, self.capacity);
    self.data = ndata;
}

pub fn push(self: *Self, data: []const u8) !void {
    if (data.len == 0) return;

    const os = self.size;
    try self.expand_capacity(data.len);
    try @memcpy(self.data[os..], data);
}

pub fn push_ex(self: *Self, size: u64) !void {
    if (size == 0) return;

    try self.expand_capacity(size);
}

pub fn get_writable_data(self: Self) void {
    return self.data[self.size..];
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.data);
}
