const std = @import("std");
const linux = std.os.linux;
const nexlog = @import("nexlog");
const debug = std.debug.print;

// Constants
const name: []const u8 = "0.0.0.0";
const port = 18888;
const buff_size = 4096;
const needle = "\n";

const Queue = @import("utils").queue.Queue;

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
        try tp.spawn(handle_connection, .{ connection, allocator });
    }
}

// fn handle_request(req: []const u8, que: Queue, alloc: std.mem.Allocator) []u8 {
//     if (req.len == 0) return &[_]u8{};
//
//     var parsed = std.json.parseFromSlice(u8, alloc, req, .{}) catch {
//
//     };
// }

fn handle_connection(connection: std.net.Server.Connection, alloc: std.mem.Allocator) void {
    const stream = connection.stream;
    defer stream.close();

    var recvqu = Queue.init(alloc, buff_size) catch {
        debug("\tERROR: Failed to allocate recvqu memory", .{});
        return;
    };
    defer recvqu.deinit();
    var sendqu = Queue.init(alloc, buff_size) catch {
        debug("\tERROR: Failed to allocate sendqu memory", .{});
        return;
    };
    defer sendqu.deinit();

    while (true) {
        debug("\twaiting for some data...\n", .{});
        var data = recvqu.get_writable_data();
        const bytes = stream.read(data) catch 0;
        if (bytes == 0) {
            debug("\tERROR: error, or closing request either way... closing this connection\n", .{});
            return;
        }

        recvqu.push_ex(bytes) catch {
            debug("\tERROR: Failed to push_ex", .{});
            return;
        };

        // Check if we have a full message
        const datapeek = recvqu.peek();
        var idx = std.mem.indexOf(u8, datapeek, needle);
        if (idx == null) continue;

        // We do have at least 1 full message
        const dataall = recvqu.pop();
        var start: usize = 0;
        // Process all the received messages in order
        while (true) {
            // TODO: Process message from dataall[start..idx]
            // - We got a full message, decode it
            // TODO: Use the json goodness here
            // TODO: Queue response
            const req = parse_request(dataall[start..idx], alloc);

            // TODO: Update start and idx
            start = idx.? + 1;
            idx = std.mem.indexOf(u8, dataall[start..], needle);
            if (idx == null) break; // No more messages to process
        }

        // TODO: Send response

        debug("\treceived some bytes = {}!!\n", .{bytes});
        stream.writeAll(data[0..bytes]) catch |err| {
            debug("\tERROR: error sendAll function {}... closing this connection\n", .{err});
            return;
        };
    }
}
