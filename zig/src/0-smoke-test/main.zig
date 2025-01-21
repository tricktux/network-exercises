const std = @import("std");
const linux = std.os.linux;
const nexlog = @import("nexlog");
const debug = std.debug.print;

const Queue = @import("Queue.zig");

fn recv_data(client: std.net.Stream, queue: *Queue) !i32 {
    while (true) {
        const data = queue.get_writable_data();
        const bytes = try client.read(data);
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

    // Constants
    const name: []const u8 = "0.0.0.0";
    const port = 18888;
    const buff_size = 1048576;

    // Create server
    var server: std.net.Server = undefined;
    defer server.deinit();
    {
        const addrlist = try std.net.getAddressList(allocator, name, port);
        defer addrlist.deinit();
        debug("Got Addresses: '{s}'!!!\n", .{addrlist.canon_name.?});

        for (addrlist.addrs) |addr| {
            debug("Trying to listen...\n", .{});
            // Not intuitive but `listen` calls `socket, bind, and listen`
            server = addr.listen(.{}) catch continue;
            break;
        }
    }

    var queue = try Queue.init(allocator, buff_size);

    debug("We are listeninig baby!!!...\n", .{});
    while (true) {
        debug("waiting for a new connection...\n", .{});
        const connection = try server.accept();

        debug("got new connection!!!\n", .{});
        while (true) {
            debug("\twaiting for some data...\n", .{});
            const stream = connection.stream;
            const r = recv_data(stream, &queue) catch -1;
            switch (r) {
                0 => {
                    debug("\treceived request to close this connection. bye bye\n", .{});
                    stream.close();
                    break;
                },
                1 => {
                    const data = queue.pop();
                    debug("\treceived some data.len = {}!!\n", .{data.len});
                    try stream.writeAll(data);
                },
                else => {
                    debug("\tERROR: closing this connection\n", .{});
                    stream.close();
                    break;
                }
            }
        }
    }
}
