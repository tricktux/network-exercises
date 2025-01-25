const std = @import("std");
const linux = std.os.linux;
const nexlog = @import("nexlog");
const debug = std.debug.print;

// Constants
const name: []const u8 = "0.0.0.0";
const port = 18888;
const buff_size = 1048576;

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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

    const cpus = try std.Thread.getCpuCount();
    var tp: std.Thread.Pool = undefined;
    try tp.init(.{ .allocator = allocator, .n_jobs = @as(u32, @intCast(cpus)) });
    defer tp.deinit();

    debug("ThreadPool initialized with {} capacity\n", .{cpus});
    debug("We are listeninig baby!!!...\n", .{});
    while (true) {
        debug("waiting for a new connection...\n", .{});
        const connection = try server.accept();
        debug("got new connection!!!\n", .{});
        try tp.spawn(handle_connection, .{connection});
    }
}

fn handle_connection(connection: std.net.Server.Connection) void {
    var data: [buff_size]u8 = undefined;
    const stream = connection.stream;
    defer stream.close();

    while (true) {
        debug("\twaiting for some data...\n", .{});
        const bytes = stream.read(&data) catch 0;
        if (bytes == 0) {
            debug("\tERROR: error, or closing request either way... closing this connection\n", .{});
            return;
        }

        debug("\treceived some bytes = {}!!\n", .{bytes});
        stream.writeAll(data[0..bytes]) catch |err| {
            debug("\tERROR: error sendAll function {}... closing this connection\n", .{err});
            return;
        };
    }
}
