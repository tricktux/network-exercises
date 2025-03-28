const std = @import("std");
const builtin = @import("builtin");
const logger = @import("logger.zig");
const messages = @import("messages.zig");
const logic = @import("logic.zig");
const types = @import("types.zig");

const linux = std.os.linux;
const testing = std.testing;
const fmt = std.fmt;
const time = std.time;
const Thread = std.Thread;

const socketfd = types.socketfd;
const Context = logic.Context;
const Cars = logic.Cars;
const Car = logic.Car;
const Roads = logic.Roads;
const Road = logic.Road;
const Cameras = logic.Cameras;
const Camera = logic.Camera;
const Tickets = logic.Tickets;
const Ticket = logic.Ticket;
const Clients = logic.Clients;
const Client = logic.Client;
const EpollManager = logic.EpollManager;
const Timers = logic.Timers;
const Timer = logic.Timer;

// Constants
const name: []const u8 = "0.0.0.0";
const port = 18888;
const kernel_backlog = 256;

// Configure logging at the root level
pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseFast => .debug,
        else => .debug,
    },
    .logFn = logger.customLogFn,
};

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the logger
    try logger.init();
    defer logger.deinit();

    // Create server
    var server: std.net.Server = undefined;
    defer server.deinit();
    {
        const addrlist = try std.net.getAddressList(allocator, name, port);
        defer addrlist.deinit();
        std.log.debug("Got Addresses: '{s}'!!!", .{addrlist.canon_name.?});
        for (addrlist.addrs) |addr| {
            std.log.debug("Trying to listen...", .{});
            // Not intuitive but `listen` calls `socket, bind, and listen`
            server = addr.listen(.{
                .kernel_backlog = kernel_backlog,
                .reuse_address = true,
                .force_nonblocking = true,
            }) catch continue;

            std.log.debug("Got one!", .{});
            break;
        }
    }

    // var tp: std.Thread.Pool = undefined;
    // try tp.init(.{ .allocator = allocator, .n_jobs = @as(u32, @intCast(cpus)) });
    // defer tp.deinit();

    // TODO Create the world
    var epoll = try EpollManager.init();
    defer epoll.deinit();
    var cars = try Cars.init(allocator);
    var roads = try Roads.init(allocator);
    var cameras = try Cameras.init(allocator);
    var tickets = Tickets.init(allocator);
    var clients = try Clients.init(allocator);
    var timers = try Timers.init(allocator);
    var ctx: Context = .{ .cars = &cars, .roads = &roads, .cameras = &cameras, .tickets = &tickets, .clients = &clients, .epoll = &epoll, .timers = &timers };

    const serverfd = server.stream.handle;
    try epoll.add(serverfd);

    // Initialize Threads
    const cpus = try std.Thread.getCpuCount();
    var threads = try std.ArrayList(std.Thread).initCapacity(allocator, cpus);
    const spawn_config = std.Thread.SpawnConfig{ .allocator = allocator };
    var i: usize = 0;
    while (i < cpus) : (i += 1) {
        const t = try std.Thread.spawn(spawn_config, handle_events, .{ &ctx, serverfd });
        try threads.append(t);
    }
    std.log.debug("Main spawned '{d}' threads", .{cpus});
    i = 0;
    while (i < cpus) : (i += 1) threads.items[i].join();
}

fn handle_events(ctx: *Context, serverfd: socketfd) void {
    const thread_id = std.Thread.getCurrentId();
    // TODO: Turn this into it's own function that the threads will spawn
    var ready_list: [kernel_backlog]linux.epoll_event = undefined;

    std.log.debug("We are listeninig baby!!!...", .{});
    while (true) {
        std.log.debug("({d}): waiting for a new event...", .{thread_id});
        // try tp.spawn(handle_connection, .{ connection, allocator });
        const ready_count = std.posix.epoll_wait(ctx.epoll.epollfd, &ready_list, -1);
        std.log.debug("got '{d}' events", .{ready_count});
        for (ready_list[0..ready_count]) |ready| {
            const ready_socket = ready.data.fd;
            defer ctx.epoll.mod(ready_socket) catch |err| {
                std.log.err("Failed to re-add socket to epoll: {!}", .{err});
            };
            // TODO: Check for timer event
            // TODO: Check for client closing event
            if (ready_socket == serverfd) {
                std.log.debug("({d}): got new connection!!!", .{thread_id});
                // TODO: do something
                // try tp.spawn(handle_connection, .{ &map, ctx, allocator });
            } else {
                // ctx.clientfd = ready_socket;
                std.log.debug("({d}): got new message!!!", .{thread_id});
                // TODO: do something
                // try tp.spawn(handle_messge, .{ &map, ctx });
            }
        }
    }
}

test {
    _ = messages;
}
