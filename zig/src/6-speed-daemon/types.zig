
const std = @import("std");
pub usingnamespace @import("messages.zig");

pub const u8BoundedArray = std.BoundedArray(u8, 1024);
