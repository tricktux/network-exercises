const std = @import("std");
const linux = std.os.linux;
const nexlog = @import("nexlog");
const debug = std.debug.print;

const Queue = @import("Queue.zig");

fn writeAll(stream: std.net.Stream, bytes: []const u8) !void {
    var index: usize = 0;
    while (index < bytes.len) {
        index += std.posix.send(stream.handle, bytes[index..], 0) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => |other_err| return other_err,
        };
    }
}

fn recv_data(client: std.net.Stream, queue: *Queue) !i32 {
    while (true) {
        const data = queue.get_writable_data();
        const bytes = client.read(data) catch |err| switch (err) {
            error.WouldBlock => return 2,
            else => |other_err| return other_err,
        };
        debug("\t\t\tpushing bytes = {}\n", .{bytes});
        try queue.push_ex(bytes);
        if (bytes == 0) return 0;
        if (bytes < data.len) return 1;
    }
}

pub fn main() !void {
    // Initialize allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Create server
    var server: std.net.Server = undefined;
    {
        const name: []const u8 = "0.0.0.0";
        const addrlist = try std.net.getAddressList(allocator, name, 18888);
        defer addrlist.deinit();
        debug("Got Addresses: '{s}'!!!\n", .{addrlist.canon_name.?});

        for (addrlist.addrs) |addr| {
            debug("Trying to listen...\n", .{});
            // Not intuitive but `listen` calls `socket, bind, and listen`
            server = addr.listen(.{}) catch continue;
            break;
        }
    }

    const listenerfd = server.stream.handle;
    defer std.posix.close(listenerfd);
    debug("We are listenning baby!!. Listening on fd = {}\n", .{listenerfd});

    // Create epoll
    const epollfd: i32 = try std.posix.epoll_create1(0);
    defer std.posix.close(epollfd);
    var epollev = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = listenerfd } };
    try std.posix.epoll_ctl(epollfd, linux.EPOLL.CTL_ADD, listenerfd, &epollev);
    const MAX_EVENTS = 128;
    var epollevents: [MAX_EVENTS]linux.epoll_event = undefined;

    // Queue
    var qu = try Queue.init(allocator, 1048576);
    defer qu.deinit();

    while (true) {
        debug("epoll_waiting...\n", .{});
        const num_events = std.posix.epoll_wait(epollfd, &epollevents, -1);
        debug("epoll got events: {}\n", .{num_events});

        for (0..num_events) |k| {
            // Process each event
            debug("\tprocessing event: {}\n", .{k});
            const eventfd = epollevents[k].data.fd;

            // Accept new connection
            if (eventfd == listenerfd) {
                var addr: std.net.Address = undefined;
                var addr_len: std.posix.socklen_t = @sizeOf(std.net.Address);
                const flags = std.posix.SOCK.NONBLOCK;
                const newfd = try std.posix.accept(eventfd, &addr.any, &addr_len, flags);

                // Add it to epoll
                var new_epollev = linux.epoll_event{ .events = linux.EPOLL.IN | linux.EPOLL.ET, .data = .{ .fd = newfd } };
                try std.posix.epoll_ctl(epollfd, linux.EPOLL.CTL_ADD, newfd, &new_epollev);
                debug("\t\taccepted new connection: {}\n", .{newfd});
                continue;
            }

            // Handle receiving data
            const stream = std.net.Stream{ .handle = eventfd };
            const r = recv_data(stream, &qu) catch -1;
            const data = qu.pop();
            debug("\t\thandle new data from eventfd: {}. data.len = {}. r = {}\n", .{eventfd, data.len, r});

            if (r <= 0) {
                // Close connection
                try std.posix.epoll_ctl(epollfd, linux.EPOLL.CTL_DEL, eventfd, &epollevents[k]);
                if (r == 0) {
                    debug("\t\tclosing connection on fd: {}\n", .{eventfd});
                } else {
                    debug("\t\tERROR: closing connection on fd: {} because of error\n", .{eventfd});
                }
                stream.close();
                continue;
            }

            // Handle data received
            if (data.len == 0) {
                debug("\t\tempty data received fd: {}. continuing...\n", .{eventfd});
                continue;
            }
            debug("\t\tSending data back to fd: {}. data.len = {}\n", .{eventfd, data.len});
            try writeAll(stream, data);
        }
    }
}

test {
    _ = @import("Queue.zig");
}
