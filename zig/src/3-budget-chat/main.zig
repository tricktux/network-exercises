const std = @import("std");
const linux = std.os.linux;
const debug = std.debug.print;
const testing = std.testing;
const fmt = std.fmt;
const time = std.time;
const Thread = std.Thread;
const u8fifo = std.fifo.LinearFifo(u8, .Dynamic);

// Constants
const name: []const u8 = "0.0.0.0";
const port = 18888;
const needle = "\n";

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Create server
    var server: std.net.Server = undefined;
    defer server.deinit();
    {
        const addrlist = try std.net.getAddressList(allocator, name, port);
        defer addrlist.deinit();
        debug("Got Addresses: '{s}'!!!\n", .{addrlist.canon_name.?});

        for (addrlist.addrs) |addr| {
            debug("\tTrying to listen...\n", .{});
            // Not intuitive but `listen` calls `socket, bind, and listen`
            server = addr.listen(.{}) catch continue;
            debug("\tGot one!\n", .{});
            break;
        }
    }

    // Initialize thread pool
    const cpus = try std.Thread.getCpuCount();
    var tp: std.Thread.Pool = undefined;
    try tp.init(.{ .allocator = allocator, .n_jobs = @as(u32, @intCast(cpus)) });
    defer tp.deinit();

    var clients = Clients.init(allocator);
    defer clients.deinit();

    debug("ThreadPool initialized with {} capacity\n", .{cpus});
    debug("We are listeninig baby!!!...\n", .{});
    const thread_id = std.Thread.getCurrentId();
    while (true) {
        debug("INFO({d}): waiting for a new connection...\n", .{thread_id});
        const connection = try server.accept();
        debug("INFO({d}): got new connection!!!\n", .{thread_id});
        try tp.spawn(handle_connection, .{ connection, &clients, allocator });
    }
}

const Clients = struct {
    clients: std.StringArrayHashMap(Client) = undefined,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) Clients {
        return Clients{ .clients = std.StringArrayHashMap(Client).init(allocator) };
    }

    pub fn deinit(self: *Clients) void {
        self.clients.deinit();
    }

    pub fn exists(self: *Clients, client: *Client) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.clients.contains(client.username.constSlice());
    }

    pub fn add(self: *Clients, client: *Client) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.clients.contains(client.username.constSlice())) return error.ClientAlreadyExists;
        try self.clients.put(client.username.constSlice(), client.*);
    }

    pub fn get_usernames(self: *Clients) []const []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.clients.keys();
    }

    pub fn remove(self: *Clients, client: *Client) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.clients.swapRemove(client.username.constSlice());
    }

    pub fn send_message(self: *Clients, message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.clients.values()) |client| {
            if (client.joined) {
                try client.stream.writeAll(message);
            }
        }
    }

    // TODO: Not working. Needs test
    pub fn send_message_from(self: *Clients, from: Client, message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Get the index of the client
        const idx = self.clients.getIndex(from.username.constSlice());
        if (idx == null) return error.ClientNotFound;

        // Iterate in order
        var it = self.clients.iterator();
        var count: usize = 0;
        while (it.next()) |entry| : (count += 1) {
            if (count == idx.?) continue;
            const client = entry.value_ptr.*;
            if (client.joined) {
                try client.stream.writeAll(message);
            }
        }
    }
};

const Client = struct {
    stream: std.net.Stream = undefined,
    joined: bool = false,
    username: std.BoundedArray(u8, 32) = undefined,

    pub fn init(stream: std.net.Stream) Client {
        return Client{ .stream = stream };
    }

    pub fn validate_username(self: *Client, username: []const u8) bool {
        if (username.len > 32) return false;
        if (username.len < 1) return false;
        for (username) |c| {
            if (!std.ascii.isAlphanumeric(c)) return false;
        }

        self.username.appendSlice(username) catch unreachable;
        self.joined = true;
        return true;
    }
};

// TODO: Add argument to handle_connection to pass the clients struct
fn handle_connection(connection: std.net.Server.Connection, clients: *Clients, alloc: std.mem.Allocator) void {
    const thread_id = std.Thread.getCurrentId();

    const stream = connection.stream;
    defer stream.close();

    var recv_fifo = std.fifo.LinearFifo(u8, .Dynamic).init(alloc);
    defer recv_fifo.deinit();

    var client = Client.init(stream);
    stream.writeAll("Welcome to budgetchat! What shall I call you?\n") catch |err| {
        debug("\t\tERROR({d}): error sendAll function {!}... closing this connection\n", .{ thread_id, err });
        return;
    };

    var msg_buffer = std.BoundedArray(u8, 1024).init(0) catch |err| {
        debug("\tERROR({d}): error while initializing msg_buffer: {!}\n", .{ thread_id, err });
        return;
    };

    defer {
        if (client.joined) {
            debug("\t\tWARN({d}): Client: {s} leaving chat...\n", .{ thread_id, client.username.constSlice() });
            // TODO: format the message
            _ = std.fmt.bufPrint(&msg_buffer.buffer, "* {s} has left the room\n", .{client.username.constSlice()}) catch |err| {
                debug("\tERROR({d}): error while formatting message: {!}\n", .{ thread_id, err });
            };
            clients.send_message_from(client, msg_buffer.constSlice()) catch |err| {
                debug("\tERROR({d}): error while sending message: {!}\n", .{ thread_id, err });
            };
            clients.remove(&client);
        }
    }

    while (true) {
        debug("\tINFO({d}): waiting for some data...\n", .{thread_id});
        const data = recv_fifo.writableWithSize(std.mem.page_size * 4) catch |err| {
            debug("\tERROR({d}): error while recv_fifo.writableWithSize: {!}\n", .{ thread_id, err });
            return;
        };

        const bytes = stream.read(data) catch |err| {
            debug("\tERROR({d}): error {!}... closing this connection\n", .{ thread_id, err });
            return;
        };
        if (bytes == 0) {
            debug("\t\tWARN({d}): Client closing this connection\n", .{
                thread_id,
            });
            return;
        }

        recv_fifo.update(bytes);

        // Check if we have a full message
        const datapeek = recv_fifo.readableSlice(0);
        // TODO: Maybe switch to using readUntilDelimiterOrEnd
        // Danger here of sending out more than one message
        const idx = std.mem.lastIndexOf(u8, datapeek, needle);
        if (idx == null) continue;

        // Clean up
        defer recv_fifo.discard(recv_fifo.readableLength());
        defer msg_buffer.clear();

        const msg = datapeek[0..idx.?];

        // Validate username?
        if (!client.joined) {
            debug("\t\tINFO({d}): Validating username...\n", .{thread_id});
            if (!client.validate_username(msg)) {
                stream.writeAll("Invalid username. Please try again.\n") catch |err| {
                    debug("\t\tERROR({d}): error sendAll function {!}... closing this connection\n", .{ thread_id, err });
                    return;
                };

                debug("\t\tWARN({d}): Invalid username: '{s}'. Closing connection.\n", .{ thread_id, msg });
                return;
            }

            // Ensure unique usernames
            if (clients.exists(&client)) {
                stream.writeAll("Username already taken. Please try again.\n") catch |err| {
                    debug("\t\tERROR({d}): error sendAll function {!}... closing this connection\n", .{ thread_id, err });
                    return;
                };
                debug("\t\tWARN({d}): Username already taken: '{s}'. Closing connection.\n", .{ thread_id, msg });
                return;
            }

            // Message new client with friends in the chat
            debug("\t\tINFO({d}): Sending room contents to new client...\n", .{thread_id});
            msg_buffer.appendSlice("* The room contains: ") catch unreachable;
            var first: bool = false;
            const usernames = clients.get_usernames();
            for (usernames) |username| {
                if (!first) {
                    first = true;
                } else {
                    msg_buffer.appendSlice(", ") catch unreachable;
                }
                msg_buffer.appendSlice(username) catch unreachable;
            }
            msg_buffer.appendSlice("\n") catch unreachable;
            stream.writeAll(msg_buffer.constSlice()) catch |err| {
                debug("\t\tERROR({d}): error sendAll function {!}... closing this connection\n", .{ thread_id, err });
                return;
            };

            // Message existing friends about the new friend in the chat
            debug("\t\tINFO({d}): Sending message to existing clients about new client...\n", .{thread_id});
            msg_buffer.clear();
            _ = std.fmt.bufPrint(&msg_buffer.buffer, "* {s} has entered the room\n", .{client.username.constSlice()}) catch |err| {
                debug("\tERROR({d}): error while formatting message: {!}\n", .{ thread_id, err });
                return;
            };
            clients.send_message(msg_buffer.constSlice()) catch |err| {
                debug("\tERROR({d}): error while sending message: {!}\n", .{ thread_id, err });
                return;
            };

            // Add to list of clients
            debug("\t\tINFO({d}): Adding client.username: {s} to clients...\n", .{ thread_id, client.username.constSlice() });
            clients.add(&client) catch |err| {
                debug("\tERROR({d}): error while adding client to clients: {!}\n", .{ thread_id, err });
                return;
            };

            continue;
        }

        debug("\t\tINFO({d}): Sending message: {s} to all clients...\n", .{ thread_id, msg });
        // TODO: format the message
        _ = std.fmt.bufPrint(&msg_buffer.buffer, "[{s}] {s}\n", .{ client.username.constSlice(), msg }) catch |err| {
            debug("\tERROR({d}): error while formatting message: {!}\n", .{ thread_id, err });
            return;
        };
        clients.send_message_from(client, msg) catch |err| {
            debug("\tERROR({d}): error while sending message: {!}\n", .{ thread_id, err });
            return;
        };
    }
}

test "Clients and Client" {
    const allocator = std.testing.allocator;
    var clients = Clients.init(allocator);
    defer clients.deinit();

    // Test Client
    // var stream = try std.net.tcpConnectToHost(allocator, "localhost", 8080);
    // defer stream.close();
    const stream = undefined;
    var client = Client.init(stream);

    try testing.expectEqual(false, client.validate_username(""));
    try testing.expectEqual(false, client.validate_username("a" ** 33));
    try testing.expectEqual(false, client.validate_username("invalid@username"));
    try testing.expectEqual(true, client.validate_username("validUsername123"));
    try testing.expectEqualStrings("validUsername123", client.username.constSlice());
    try testing.expect(client.joined);

    // Test Clients
    try testing.expect(!clients.exists(&client));
    try clients.add(&client);
    try testing.expect(clients.exists(&client));

    const usernames = clients.get_usernames();
    try testing.expectEqual(@as(usize, 1), usernames.len);
    try testing.expectEqualStrings("validUsername123", usernames[0]);

    clients.remove(&client);
    try testing.expect(!clients.exists(&client));

    // Test message sending (this is more of a mock test)
    var client2 = Client.init(stream);
    _ = client2.validate_username("anotherUser");
    try clients.add(&client);
    try clients.add(&client2);

    // clients.send_message("Hello, everyone!");
    // clients.send_message_from(client, "Hello from validUsername123");
}

// Import the main function and other necessary components
const main_module = @import("main.zig");

fn runServer() !void {
    try main_module.main();
}

fn simulateClient(allocator: std.mem.Allocator) !void {
    // Wait a bit for the server to start
    // Wait for 2 seconds
    time.sleep(2000000000);

    var client = try std.net.tcpConnectToHost(allocator, "127.0.0.1", 18888);
    defer client.close();

    var buffer: [1024]u8 = undefined;

    // Read welcome message
    const welcome_msg = try client.reader().readUntilDelimiter(&buffer, '\n');
    try testing.expectEqualStrings("Welcome to budgetchat! What shall I call you?", welcome_msg);

    // Send username
    try client.writer().writeAll("testuser\n");

    // Read room contents
    const room_msg = try client.reader().readUntilDelimiter(&buffer, '\n');
    try testing.expect(std.mem.startsWith(u8, room_msg, "* The room contains:"));

    // Send a message
    try client.writer().writeAll("Hello, world!\n");

    // Close the connection
    client.close();
}

test "Server and Client Integration Test" {
    const allocator = std.testing.allocator;

    // Start the server in a separate thread
    var server_thread = try Thread.spawn(.{}, runServer, .{});

    // Run the client simulation
    try simulateClient(allocator);

    // Note: In a real scenario, you'd want to gracefully shut down the server.
    // For this test, we'll just detach the thread and let it run.
    server_thread.detach();
}
