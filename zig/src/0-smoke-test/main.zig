const std = @import("std");
const linux = std.os.linux;
const nexlog = @import("nexlog");

const Queue = @import("Queue.zig").Queue;

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

    const listenerfd = server.stream.handle;
    try logger.log(.trace, "We are listenning baby!!. Listening on fd = {}", .{listenerfd}, base_metadata);

    // Epoll init
    const epollfd: i32 = try std.posix.epoll_create1(0);
    var epollev = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{.fd = listenerfd} };
    try std.posix.epoll_ctl(epollfd, linux.EPOLL.CTL_ADD, listenerfd, &epollev);
    const MAX_EVENTS = 128;
    var epollevents: [MAX_EVENTS]linux.epoll_event = undefined;

    // Queue
    const qu = try Queue.init(allocator, @as(u64, 1024));
    _ = qu;

    while(true) {
        try logger.flush();
        try logger.log(.trace, "epoll_waiting...", .{}, base_metadata);
        const num_events = std.posix.epoll_wait(epollfd, &epollevents, -1);
        try logger.log(.trace, "epoll got events: {}\n", .{num_events}, base_metadata);

        for (epollevents[0..num_events]) |event| {
            // Process each event
            const eventfd = event.data.fd;

            // Accept new connection
            if (eventfd == listenerfd) {
                var addr: std.net.Address = undefined;
                var addr_len: std.posix.socklen_t = @sizeOf(std.net.Address);
                const flags = std.posix.SOCK.NONBLOCK | std.posix.SOCK.CLOEXEC;
                const newfd = try std.posix.accept(eventfd, &addr.any, &addr_len, flags);

                // Add it to epoll
                var new_epollev = linux.epoll_event{ .events = linux.EPOLL.IN | linux.EPOLL.ET, .data = .{.fd = newfd} };
                try std.posix.epoll_ctl(epollfd, linux.EPOLL.CTL_ADD, newfd, &new_epollev);
                try logger.log(.info, "accepted new connection: {}\n", .{newfd}, base_metadata);
                continue;
            }

            // Handle receiving data
            try logger.log(.trace, "Handle new data from eventfd: {}\n", .{eventfd}, base_metadata);
        }
    }

}
