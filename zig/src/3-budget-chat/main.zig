const std = @import("std");
const linux = std.os.linux;
const debug = std.debug.print;
const testing = std.testing;
const fmt = std.fmt;
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

    pub fn send_message_from(self: *Clients, from: Client, message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.clients.values()) |client| {
            if (client == from) continue;
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

    var send_fifo = std.fifo.LinearFifo(u8, .Dynamic).init(alloc);
    defer send_fifo.deinit();

    var client = Client.init(stream);
    stream.writeAll("Welcome to budgetchat! What shall I call you?") catch |err| {
        debug("\t\tERROR({d}): error sendAll function {!}... closing this connection\n", .{ thread_id, err });
        return;
    };
    defer clients.remove(&client);

    var msg_buffer = std.BoundedArray(u8, 1024).init(0) catch |err| {
        debug("\tERROR({d}): error while initializing msg_buffer: {!}\n", .{ thread_id, err });
        return;
    };

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
        const idx = std.mem.lastIndexOf(u8, datapeek, needle);
        if (idx == null) continue;

        // Validate username?
        if (!client.joined) {
            if (!client.validate_username(datapeek[0..idx.?])) {
                stream.writeAll("Invalid username. Please try again.") catch |err| {
                    debug("\t\tERROR({d}): error sendAll function {!}... closing this connection\n", .{ thread_id, err });
                    return;
                };

                debug("\t\tWARN({d}): Invalid username: '{s}'. Closing connection.\n", .{ thread_id, datapeek[0..idx.?] });
                return;
            }

            // Message new client with friends in the chat
            msg_buffer.clear();
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
            msg_buffer.clear();
            _ = std.fmt.bufPrint(&msg_buffer.buffer, "* {} has entered the room\n", .{ client.username }) catch |err| {
                debug("\tERROR({d}): error while formatting message: {!}\n", .{ thread_id, err });
                return;
            };
            clients.send_message(msg_buffer.constSlice()) catch |err| {
                debug("\tERROR({d}): error while sending message: {!}\n", .{ thread_id, err });
                return;
            };

            // Add to list of clients
            clients.add(&client) catch |err| {
                debug("\tERROR({d}): error while adding client to clients: {!}\n", .{ thread_id, err });
                return;
            };
        }

        // Send response
        const resp = send_fifo.readableSlice(0);
        if (resp.len > 0) {
            // debug("\t\tINFO({d}): sending response of size: '{d}'\n", .{ thread_id, resp.len });
            stream.writeAll(resp) catch |err| {
                debug("\t\tERROR({d}): error sendAll function {!}... closing this connection\n", .{ thread_id, err });
                return;
            };
            send_fifo.discard(resp.len);
        }

        recv_fifo.discard(recv_fifo.readableLength());
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
