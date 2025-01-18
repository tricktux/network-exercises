const std = @import("std");
const nexlog = @import("nexlog");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Create base metadata
    const base_metadata = nexlog.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 0,
        .file = @src().file,
        .line = @src().line,
        .function = @src().fn_name,
    };

    // Initialize logger with small file size to demonstrate rotation
    var builder = nexlog.LogBuilder.init();
    try builder
        .setMinLevel(.trace)
        .enableColors(true)
        .setBufferSize(4096)
        .enableFileLogging(true, "/tmp/smoke-tests-zig.logs")
        .setMaxFileSize(1073741824) // 10Mb
        .setMaxRotatedFiles(3) // Keep 3 backup files
        .enableRotation(true)
        .build(allocator);

    defer nexlog.deinit();

    const logger = nexlog.getDefaultLogger() orelse return error.LoggerNotInitialized;

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    try logger.log(.trace, "Hello world!", .{}, base_metadata);
    try logger.flush();
}
