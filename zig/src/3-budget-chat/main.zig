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

    // TODO: Initialize clients

    debug("ThreadPool initialized with {} capacity\n", .{cpus});
    debug("We are listeninig baby!!!...\n", .{});
    const thread_id = std.Thread.getCurrentId();
    while (true) {
        debug("INFO({d}): waiting for a new connection...\n", .{thread_id});
        const connection = try server.accept();
        debug("INFO({d}): got new connection!!!\n", .{thread_id});
        try tp.spawn(handle_connection, .{ connection, allocator });
    }
}

const Clients = struct {
    clients: std.ArrayHashMapWithAllocator = undefined,
    mutex: std.Mutex = std.Mutex.init,

    pub fn init(allocator: *std.mem.Allocator) Clients {
        return Clients{ .clients = std.StringArrayHashMap(Client).init(allocator) };
    }

    pub fn deinit(self: *Clients) void {
        self.clients.deinit();
    }
    pub fn try_add(self: *Clients, client: *Client) void {
        self.clients.put(client.username, client);
    }

    // TODO: Add remove function
    // pub fn try_remove(self: *Clients, username: []const u8) void {
    //     self.clients.remove(username);
    // }
};

const Client = struct {
    stream: std.net.Stream = undefined,
    joined: bool = false,
    username: [32]u8 = undefined,

    pub fn init(stream: std.net.Stream) Client {
        return Client{ .stream = stream };
    }

    pub fn validate_username(self: *Client, username: []const u8) bool {
        if (username.len > 32) return false;
        if (username.len < 1) return false;
        for (username) |c| {
            if (!std.ascii.isAlphanumeric(c)) return false;
        }
        // self.username = username;
        @memcpy(self.username[0..username.len], username);
        self.joined = true;
        return true;
    }
};

// TODO: Add argument to handle_connection to pass the clients struct
fn handle_connection(connection: std.net.Server.Connection, alloc: std.mem.Allocator) void {
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

            // Send client members
            var send_writer = send_fifo.writer();
            _ = send_writer.write("* The room contains: ") catch |err| {
                debug("\tERROR({d}): error while send_fifo.writer.print: {!}\n", .{ thread_id, err });
                return;
            };

            // send_writer.write(client.username) catch |err| {
            //     debug("\tERROR({d}): error while send_fifo.writer.write: {!}\n", .{ thread_id, err });
            //     return;
            // };
            // var friends = send_fifo.writableWithSize(1024) catch |err| {
            //     debug("\tERROR({d}): error while send_fifo.writableWithSize: {!}\n", .{ thread_id, err });
            //     return;
            // };
            // friends.append("* The room contains: ");
            // friends.
            // Add to list of clients

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
