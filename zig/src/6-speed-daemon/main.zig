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
const MessageBoundedArray = messages.MessageBoundedArray;
const u8BoundedArray = types.u8BoundedArray;
const Message = messages.Message;
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
const Fifos = logic.Fifos;

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
    // TODO: Add fifos
    var epoll = try EpollManager.init();
    defer epoll.deinit();
    var fifos = try Fifos.init(allocator);
    defer fifos.deinit();
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
    var ctx: Context = .{ .cars = &cars, .roads = &roads, .cameras = &cameras, .tickets = &tickets, .clients = &clients, .epoll = &epoll, .timers = &timers, .fifos = &fifos };

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

const ThreadContext = struct {
    buf: *u8BoundedArray,
    fd: socketfd,
    client: ?*Client,
    error_msg: ?[]const u8,
};

inline fn removeFd(ctx: *Context, thr_ctx: *ThreadContext) void {
    if (thr_ctx.client != null) {
        if (thr_ctx.error_msg != null) {
            thr_ctx.client.sendError(thr_ctx.error_msg, &thr_ctx.buf) catch |err| {
                std.log.err("Failed to client.sendError: {!}", .{err});
            };
        }
        ctx.clients.del(thr_ctx.fd, ctx.epoll) catch |third_err| {
            std.log.err("Failed to del client: {!}", .{third_err});
        };
    } else {
        ctx.epoll.del(thr_ctx.fd) catch |err| {
            std.log.err("Failed to del epoll: {!}", .{err});
        };
    }

    ctx.fifos.del(thr_ctx.fd) catch |err| {
        std.log.err("Failed to del fifo: {!}", .{err});
    };
}

// TODO: Create this thread context also at the beginning of the function
// TODO: - Remember to update members as you update functions
// TODO: On new client create a new fifo
// TODO: On message receipt use the fifo
// TODO: On client disconnect remove the fifo
// TODO: Streamline functions
// TODO: - Like message handling

fn handle_events(ctx: *Context, serverfd: socketfd, alloc: std.mem.Allocator) void {
    const thread_id = std.Thread.getCurrentId();
    const cpus = std.Thread.getCpuCount() catch |err| {
        std.log.err("Failed to get CPU count: {!}", .{err});
        return;
    };

    var ready_events = std.ArrayList(linux.epoll_event).initCapacity(alloc, kernel_backlog / cpus) catch |err| {
        std.log.err("Failed to create ready_events list: {!}", .{err});
        return;
    };
    defer ready_events.deinit();
    _ = ready_events.addManyAsSlice(kernel_backlog / cpus) catch |err| {
        std.log.err("Failed to add ready_events list: {!}", .{err});
        return;
    };
    var buf = u8BoundedArray.init(0) catch |err| {
        std.log.err("Failed to create buffer: {!}", .{err});
        return;
    };
    var msgs = MessageBoundedArray.init(0) catch |err| {
        std.log.err("Failed to create messages: {!}", .{err});
        return;
    };

    var thr_ctx = ThreadContext{.fd = 0, .error_msg = null, .buf = &buf, .client = null};

    std.log.debug("We are listeninig baby!!!...", .{});
    while (true) {
        // Clean up
        buf.clear();
        for (&msgs.buffer) |*msg| msg.deinit();
        msgs.clear();

        std.log.debug("({d}): waiting for a new event...", .{thread_id});
        const ready_count = std.posix.epoll_wait(ctx.epoll.epollfd, ready_events.items, -1);
        std.log.debug("got '{d}' events", .{ready_count});
        for (ready_events.items[0..ready_count]) |event| {
            const ready_socket = event.data.fd;
            // TODO: even timers need this?
            defer ctx.epoll.mod(ready_socket) catch |err| {
                std.log.err("Failed to re-add socket to epoll: {!}", .{err});
            };
            const client = ctx.clients.get(ready_socket);
            thr_ctx.client = client;
            thr_ctx.fd = ready_socket;

            // Check for timer event
            if (ctx.timers.get(ready_socket)) |timer| {
                const clientfd = timer.client.fd;
                timer.read() catch |err| {
                    std.log.err("Failed to posix.read timer: {!}...deleting client...", .{err});
                    thr_ctx.client = timer.client;
                    timer.client.sendError("Failed to posix.read timer", &buf) catch |sec_err| {
                        std.log.err("Failed to client.sendError: {!}", .{sec_err});
                    };
                    ctx.clients.del(clientfd, ctx.epoll) catch |third_err| {
                        std.log.err("Failed to del client: {!}", .{third_err});
                    };
                    continue;
                };

                timer.client.sendHeartbeat(&buf) catch |err| {
                    std.log.err("Failed to client.sendHeartbeat: {!}", .{err});
                    timer.client.sendError("Failed to sendHeartbeat", &buf) catch |sec_err| {
                        std.log.err("Failed to client.sendError: {!}", .{sec_err});
                    };
                    ctx.clients.del(clientfd, ctx.epoll) catch |third_err| {
                        std.log.err("Failed to del client: {!}", .{third_err});
                    };
                    continue;
                };
                std.log.debug("({d}): Sent heartbeat to client: {d}", .{ thread_id, timer.client.fd });
                continue;
            }

            if ((event.events & linux.EPOLL.RDHUP) == linux.EPOLL.RDHUP) {
                // TODO: Can't assume this is a client
                ctx.clients.del(ready_socket, ctx.epoll) catch |err| {
                    std.log.err("Failed to del client: {!}", .{err});
                    continue;
                };
                std.log.debug("({d}): Closed connection for client: {d}", .{ thread_id, ready_socket });
                continue;
            }

            if (ready_socket == serverfd) {
                std.log.debug("({d}): got new connection!!!", .{thread_id});

                const clientfd = std.posix.accept(serverfd, null, null, std.posix.SOCK.NONBLOCK | std.posix.SOCK.CLOEXEC) catch |err| {
                    std.log.err("({d}): error while accepting connection: {!}", .{ thread_id, err });
                    continue;
                };
                // For now just add it to epoll, until it identifies itself
                ctx.epoll.add(clientfd) catch |err| {
                    std.log.err("({d}): error while accepting connection: {!}", .{ thread_id, err });
                };

                continue;
            }

            // Then it must be we got a new message
            std.log.debug("({d}): got new message!!!", .{thread_id});
            // TODO: do something
            // - Read the messages
            const stream = std.net.Stream{ .handle = ready_socket };

            // TODO: Need fifo here
            var bytes: usize = 0;
            var read_error = false;
            while (true) {
                bytes = stream.read(buf.buffer[bytes..]) catch |err| {
                    switch (err) {
                        error.WouldBlock => break,
                        else => {
                            std.log.err("error while reading from client: {!}", .{err});
                            read_error = true;
                            break;
                        },
                    }
                };
                if (bytes == 0) break;
                if (bytes >= 2048) {
                    std.log.err("Too many bytes read: {d}", .{bytes});
                    break;
                }
                buf.len += bytes;
            }

            if (read_error) {
                std.log.err("({d}): error while reading from client: {!}", .{thread_id, ready_socket});
                if (client != null) {
                    ctx.clients.del(ready_socket, ctx.epoll) catch |err| {
                        std.log.err("Failed to del client: {!}", .{err});
                    };
                }
                ctx.epoll.del(ready_socket) catch |err| {
                    std.log.err("Failed to del client: {!}", .{err});
                };
                continue;
            }

            // - Handle read zero byte
            if (bytes == 0) {
                if (client != null) {
                    std.log.debug("({d}): Client disconnected: {d}", .{thread_id, ready_socket});
                    ctx.clients.del(ready_socket, ctx.epoll) catch |err| {
                        std.log.err("Failed to del client: {!}", .{err});
                    };
                    continue;
                }

                std.log.debug("({d}): Client disconnected before identifying: {d}", .{thread_id, ready_socket});
                ctx.epoll.del(ready_socket) catch |err| {
                    std.log.err("Failed to del client: {!}", .{err});
                };
                continue;
            }
            // - call decode(buf, msgs)
            _ = messages.decode(buf.constSlice(), &msgs, alloc) catch |err| {
                std.log.err("Failed to decode messages: {!}", .{err});
                continue;
            };
            // - for (msgs) |msg| { switch (msg.Type) { ... } }
            for (&msgs.buffer) |*msg| {
                switch (msg.type) {
                    messages.Type.Heartbeat => {
                        if (client == null) {
                            std.log.err("({d}): Got heartbeat from unknown client: {d}", .{thread_id, ready_socket});
                            continue;
                        }
                        std.log.debug("({d}): Got heartbeat from client: {d}", .{thread_id, ready_socket});
                        // client.heartbeat();
                    },
                    else => {
                        std.log.err("Unrecognized error message", .{});
                    }
                }
            }
        }
    }
}

test {
    _ = messages;
    _ = logic;
}
