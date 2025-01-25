const std = @import("std");
const linux = std.os.linux;
const nexlog = @import("nexlog");
const debug = std.debug.print;

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

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
            debug("\tTrying to listen...\n", .{});
            // Not intuitive but `listen` calls `socket, bind, and listen`
            server = addr.listen(.{}) catch continue;
            debug("\tGot one!\n", .{});
            break;
        }
    }

    var data: [buff_size]u8 = undefined;

    debug("We are listeninig baby!!!...\n", .{});
    while (true) {
        debug("waiting for a new connection...\n", .{});
        const connection = try server.accept();

        debug("got new connection!!!\n", .{});
        while (true) {
            debug("\twaiting for some data...\n", .{});
            const stream = connection.stream;
            const bytes = stream.read(&data) catch 0;
            if (bytes == 0) {
                debug("\tERROR: error, or closing request either way... closing this connection\n", .{});
                stream.close();
                break;
            }

            debug("\treceived some data.len = {}!!\n", .{data.len});
            try stream.writeAll(&data);
        }
    }
}
