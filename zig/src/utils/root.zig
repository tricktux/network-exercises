
const std = @import("std");

pub const queue = @import("Queue.zig");

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}
