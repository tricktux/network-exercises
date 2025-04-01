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
const TicketsQueue = logic.TicketsQueue;
const EpollManager = logic.EpollManager;
const Timers = logic.Timers;
const Timer = logic.Timer;
const Clients = logic.Clients;
const Client = logic.Client;

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

    // Create the world
    var epoll = try EpollManager.init();
    defer epoll.deinit();
    var tickets = TicketsQueue.init(allocator);
    defer tickets.deinit();
    var cars = try Cars.init(allocator, &tickets);
    defer cars.deinit();
    var roads = try Roads.init(allocator);
    defer roads.deinit();
    var cameras = try Cameras.init(allocator);
    defer cameras.deinit();
    var clients = try Clients.init(allocator);
    defer clients.deinit(&epoll) catch |err| {
        std.log.err("Failed to deinit clients: {!}", .{err});
    };
    var timers = try Timers.init(allocator);
    defer timers.deinit();
    var ctx: Context = .{ .cars = &cars, .roads = &roads, .cameras = &cameras, .tickets = &tickets, .clients = &clients, .epoll = &epoll, .timers = &timers };

    const serverfd = server.stream.handle;
    try epoll.add(serverfd);

    // Initialize Threads
    const cpus = try std.Thread.getCpuCount();
    var threads = try std.ArrayList(std.Thread).initCapacity(allocator, cpus);
    defer threads.deinit();
    _ = try threads.addManyAsSlice(cpus);
    const spawn_config = std.Thread.SpawnConfig{ .allocator = allocator };

    // Spawn threads
    var i: usize = 0;
    while (i < cpus) : (i += 1) {
        threads.items[i] = try std.Thread.spawn(spawn_config, handle_events, .{ &ctx, serverfd, allocator });
    }
    std.log.debug("Main spawned '{d}' threads", .{cpus});
    i = 0;
    while (i < cpus) : (i += 1) threads.items[i].join();
}

fn handle_events(ctx: *Context, serverfd: socketfd, alloc: std.mem.Allocator) void {
    const thread_id = std.Thread.getCurrentId();
    const cpus = std.Thread.getCpuCount() catch |err| {
        std.log.err("Failed to get CPU count: {!}", .{err});
        return;
    };

    var ready_events = std.ArrayList(linux.epoll_event).initCapacity(alloc, kernel_backlog/cpus) catch |err| {
        std.log.err("Failed to create ready_events list: {!}", .{err});
        return;
    };
    _ = ready_events.addManyAsSlice(kernel_backlog/cpus) catch |err| {
        std.log.err("Failed to add ready_events list: {!}", .{err});
        return;
    };
    defer ready_events.deinit();


    std.log.debug("We are listeninig baby!!!...", .{});
    while (true) {
        std.log.debug("({d}): waiting for a new event...", .{thread_id});
        // try tp.spawn(handle_connection, .{ connection, allocator });
        const ready_count = std.posix.epoll_wait(ctx.epoll.epollfd, ready_events.items, -1);
        std.log.debug("got '{d}' events", .{ready_count});
        for (ready_events.items[0..ready_count]) |event| {
            const ready_socket = event.data.fd;
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
    _ = logic;
}
