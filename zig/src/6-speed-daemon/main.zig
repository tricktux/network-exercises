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
const Type = messages.Type;
const ClientType = logic.ClientType;
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
const Camera = logic.Camera;
const Tickets = logic.Tickets;
const TicketsQueue = logic.TicketsQueue;
const EpollManager = logic.EpollManager;
const Timers = logic.Timers;
const Timer = logic.Timer;
const Clients = logic.Clients;
const Client = logic.Client;
const Dispatcher = logic.Dispatcher;

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
    defer roads.deinit() catch |err| {
        std.log.err("Failed to deinit roads: {!}", .{err});
    };
    var timers = try Timers.init(allocator);
    defer timers.deinit();
    var clients = try Clients.init(allocator);
    defer clients.deinit(&timers) catch |err| {
        std.log.err("Failed to deinit clients: {!}", .{err});
    };
    var ctx: Context = .{ .cars = &cars, .roads = &roads, .tickets = &tickets, .clients = &clients, .epoll = &epoll, .timers = &timers };

    const serverfd = server.stream.handle;
    try epoll.add(serverfd);

    // handle_events(&ctx, serverfd, allocator);
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
    // TODO: Make it Not optional
    client: *Client,
    error_msg: ?[]const u8,
    msgs: *MessageBoundedArray,
    alloc: std.mem.Allocator,
};

inline fn removeFd(ctx: *Context, thr_ctx: *ThreadContext) void {
    if (thr_ctx.error_msg != null) {
        thr_ctx.client.sendError(thr_ctx.error_msg.?, thr_ctx.buf) catch |err| {
            std.log.err("Failed to client.sendError: {!}", .{err});
        };
    }

    // If it's a dispatcher, remove the roads
    if (thr_ctx.client.type == ClientType.Dispatcher) {
        ctx.roads.removeDispatcher(&thr_ctx.client.data.dispatcher) catch |err| {
            std.log.err("Failed to remove dispatcher: {!}", .{err});
        };
    }
    ctx.clients.del(thr_ctx.fd, ctx.timers) catch |third_err| {
        std.log.err("Failed to del client: {!}", .{third_err});
    };
}

// TODO: This function's length is getting out of hand
inline fn handleMessages(ctx: *Context, thr_ctx: *ThreadContext) !void {
    const fd = thr_ctx.fd;
    const stream = std.net.Stream{ .handle = fd };
    const client = thr_ctx.client;
    const thrid = std.Thread.getCurrentId();

    std.log.debug("({d}): got new message from: {d}!!!", .{ thrid, fd });

    var fifo = &thr_ctx.client.fifo;
    // TODO: Fifo not holding the data
    std.log.debug("({d}): fifo.len: {d}", .{ thrid, fifo.readableLength() });

    var bytes: usize = 0;
    while (true) {
        const buf = try fifo.writableWithSize(2048);
        bytes = stream.read(buf) catch |err| {
            switch (err) {
                error.WouldBlock => break,
                else => {
                    std.log.err("error while reading from client: {!}", .{err});
                    return err;
                },
            }
        };
        if (bytes == 0) break;
        std.log.debug("({d}): read {d} bytes from client: {d}", .{ thrid, bytes, fd });
        fifo.update(bytes);
    }

    // - Handle read zero byte
    // TODO: This would cause an error. epoll.mod will be called
    if (bytes == 0) return error.ClientClosedConnection;

    // - call decode(buf, msgs)
    const data = fifo.readableSlice(0);
    const len = try messages.decode(data, thr_ctx.msgs, thr_ctx.alloc);
    std.log.debug("({d}): data.len: {d}, len: {d}, fifo.len: {d}, msgs.len: {d}", .{ thrid, data.len, len, fifo.readableLength(), thr_ctx.msgs.len });
    if (len == 0 or thr_ctx.msgs.len == 0) {
        std.log.debug("({d}): No messages to decode for client: {d}", .{ thrid, fd });
        return;
    }

    if (len > fifo.readableLength())
        std.log.err("({d}): len: {d} > fifo.readableLength: {d}", .{ thrid, len, fifo.readableLength() });
    defer fifo.discard(len);

    const msgs = thr_ctx.msgs.slice();
    var i: usize = 0;
    while (i < msgs.len) : (i += 1) {
        const msg = &msgs[i];
        const mt = std.enums.tagName(Type, msg.type);
        const mts = if (mt == null) "unknown" else mt.?;
        switch (msg.type) {
            .Heartbeat, .ErrorM, .Ticket => {
                std.log.debug("({d}): Got unexpected msg type: {s} from client: {d}", .{ thrid, mts, fd });
                return error.UnexpectedMessageType;
            },
            .IAmCamera => {
                std.log.debug("({d}): Got {s} msg from client: {d}", .{ thrid, mts, fd });
                if (client.type != .Unidentified) {
                    const t = std.enums.tagName(ClientType, client.type);
                    const u = if (t == null) "unknown" else t.?;
                    std.log.err("({d}): Client already is identified as type: {s}", .{ thrid, u });
                    return error.ClientAlreadyIdentified;
                }

                // Set client as camera
                try client.setAsCamera(msg);
            },
            .IAmDispatcher => {
                std.log.debug("({d}): Got {s} msg from client: {d}", .{ thrid, mts, fd });
                if (client.type != .Unidentified) {
                    const t = std.enums.tagName(ClientType, client.type);
                    const u = if (t == null) "unknown" else t.?;
                    std.log.err("({d}): Client already is identified as type: {s}", .{ thrid, u });
                    return error.ClientAlreadyIdentified;
                }

                // Add dispatcher to the Dispatchers
                try client.setAsDispatcher(msg);

                // Update roads database with new dispatcher
                try ctx.roads.addDispatcher(&client.data.dispatcher, thr_ctx.alloc);

                // std.log.debug("({d}): Added dispatcher: {s}", .{ thrid, client.data.dispatcher.name });

                // Check tickets queue for any pending tickets for this new dispatcher
                try ctx.tickets.dispatchTicketsQueue(ctx.roads, thr_ctx.buf);
            },
            .WantHeartbeat => {
                std.log.debug("({d}): Got want_heartbeat msg from client: {d} with interval: {d}", .{ thrid, fd, msg.data.want_heartbeat.interval });

                // Check if there's a timer already associated with this client
                if ((client.heartbeat_requested == true) or (client.timer != null)) {
                    std.log.err("({d}): Timer already exists for client: {d}", .{ thrid, fd });
                    return error.TimerAlreadyExists;
                }
                // If there's not create a new one and attach it
                const interval = @as(u64, @intCast(msg.data.want_heartbeat.interval));
                if (interval == 0) {
                    client.heartbeat_requested = true;
                    continue;
                }

                const timer = try client.addTimer(interval);

                try ctx.timers.add(timer);
            },
            .Plate => {
                std.log.debug("({d}): Got plate msg from client: {d}", .{ thrid, fd });
                if (client.type != ClientType.Camera) {
                    std.log.err("({d}): Client not identified as camera", .{thrid});
                    return error.ClientNotIdentifiedAsCamera;
                }

                // Get Car
                var car = try ctx.cars.getOrPut(msg.data.plate.plate, ctx.tickets);

                const ntickets = try car.addObservation(msg, &client.data.camera);

                if (ntickets > 0) {
                    std.log.debug("({d}): Added {d} tickets to car: {s}", .{ thrid, ntickets, msg.data.plate.plate });

                    try ctx.tickets.dispatchTicketsQueue(ctx.roads, thr_ctx.buf);
                }
            },
            else => {
                std.log.err("Impossible!! But received a message of invalid type", .{});
                return error.InvalidMessageType;
            },
        }
        msg.deinit();
    }
}

fn handle_events(ctx: *Context, serverfd: socketfd, alloc: std.mem.Allocator) void {
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

    var thr_ctx = ThreadContext{ .fd = 0, .error_msg = null, .buf = &buf, .client = undefined, .msgs = &msgs, .alloc = alloc };
    const thrid = std.Thread.getCurrentId();

    std.log.debug("We are listeninig baby!!!...", .{});
    while (true) {
        std.log.debug("({d}): waiting for a new event...", .{thrid});
        const ready_count = std.posix.epoll_wait(ctx.epoll.epollfd, ready_events.items, -1);
        std.log.debug("got '{d}' events", .{ready_count});
        for (ready_events.items[0..ready_count]) |event| {
            // Clean up
            buf.clear();
            msgs.clear();

            const ready_socket = event.data.fd;

            // Handle a new connection event
            if (ready_socket == serverfd) {
                const clientfd = std.posix.accept(serverfd, null, null, std.posix.SOCK.NONBLOCK | std.posix.SOCK.CLOEXEC) catch |err| {
                    std.log.err("({d}): error while accepting connection: {!}", .{ thrid, err });
                    continue;
                };

                // TODO: Are these fatal errors? Should we return instead of
                // continue?
                // Create new client
                std.log.debug("({d}): got new connection: {d}!!!", .{ thrid, clientfd });

                // Add new client
                ctx.clients.add(clientfd, ctx.epoll) catch |err| {
                    std.log.err("({d}): Failed to add client: {!}", .{ thrid, err });
                    thr_ctx.error_msg = "Failed to add client";
                    removeFd(ctx, &thr_ctx);
                };
                ctx.epoll.mod(ready_socket) catch |err| switch (err) {
                    else => std.log.err("Failed to re-add socket to epoll: {!}", .{err}),
                };
                continue;
            }

            // Check for timer event
            if (ctx.timers.get(ready_socket)) |timer| {
                thr_ctx.client = timer.client;
                thr_ctx.fd = timer.client.fd;
                _ = timer.read() catch |err| {
                    std.log.err("Failed to posix.read timer: {!}...deleting client...", .{err});
                    thr_ctx.error_msg = "Failed to posix.read timer";
                    removeFd(ctx, &thr_ctx);
                    continue;
                };

                timer.client.sendHeartbeat(&buf) catch |err| {
                    std.log.err("Failed to client.sendHeartbeat: {!}", .{err});
                    thr_ctx.error_msg = "Failed to sendHeartbeat";
                    removeFd(ctx, &thr_ctx);
                    continue;
                };
                std.log.debug("({d}): Sent heartbeat to client: {d}", .{ thrid, timer.client.fd });
                ctx.epoll.mod(ready_socket) catch |err| switch (err) {
                    else => std.log.err("Failed to re-add socket to epoll: {!}", .{err}),
                };
                continue;
            }

            // Setup loop variables if it's not a timer
            const client = ctx.clients.get(ready_socket);
            if (client == null) {
                std.log.err("({d}): Failed to find client: {d}", .{ thrid, ready_socket });
                ctx.epoll.del(ready_socket) catch |err| {
                    std.log.err("Failed to del client: {!}", .{err});
                };
                continue;
            }
            thr_ctx.client = client.?;
            thr_ctx.fd = ready_socket;
            thr_ctx.error_msg = null;

            // Handle a closing connection event
            if ((event.events & linux.EPOLL.RDHUP) == linux.EPOLL.RDHUP) {
                std.log.debug("({d}): Received RDHUP for client: {d}. Bye Bye", .{ thrid, ready_socket });
                removeFd(ctx, &thr_ctx);
                continue;
            }

            // Then it must be we got a new message
            handleMessages(ctx, &thr_ctx) catch |err| switch (err) {
                error.ClientClosedConnection => {
                    std.log.debug("({d}): Client closed connection: {d}", .{ thrid, ready_socket });
                    removeFd(ctx, &thr_ctx);
                    continue;
                },
                else => {
                    std.log.err("({d}): Error while handleMessages with client: {d}. Error: {!}", .{ thrid, ready_socket, err });
                    buf.clear();
                    if (std.fmt.format(buf.writer().any(), "Error while handleMessages with client: {d}. Error: {!}", .{ ready_socket, err })) {
                        thr_ctx.error_msg = buf.constSlice();
                    } else |err2| {
                        std.log.err("Failed to format error message: {!}", .{err2});
                        thr_ctx.error_msg = "Error while handleMessages";
                    }
                    removeFd(ctx, &thr_ctx);
                    continue;
                },
            };
            ctx.epoll.mod(ready_socket) catch |err| switch (err) {
                else => std.log.err("Failed to re-add socket to epoll: {!}", .{err}),
            };
        }
    }
}

test {
    _ = messages;
    _ = logic;
}
