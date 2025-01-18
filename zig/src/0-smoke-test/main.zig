const std = @import("std");
const nexlog = @import("nexlog");

pub fn main() !void {
    // Initialize allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

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
    try logger.log(.trace, "Hello world!", .{}, base_metadata);

    // Create server
    var server: std.net.Server = undefined;
    {
        const name: []const u8 = "localhost";
        const addrlist = try std.net.getAddressList(allocator, name, 18888);
        defer addrlist.deinit();
        try logger.log(.trace, "Got Addresses: '{s}'!!!", .{addrlist.canon_name.?}, base_metadata);

        for (addrlist.addrs) |addr| {
            try logger.log(.trace, "Trying to listen...", .{}, base_metadata);
            // Not intuitive but `listen` calls `socket, bind, and listen`
            server = addr.listen(.{ .reuse_address = true }) catch continue;
            break;
        }
    }

    try logger.log(.trace, "We are listenning baby!!. Server fd = {}", .{server.stream.handle}, base_metadata);

    // Epoll init
    // const epollfd: i32 = try std.posix.epoll_create1(0);

    try logger.flush();
}
