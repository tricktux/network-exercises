const std = @import("std");
const linux = std.os.linux;
const debug = std.debug.print;
const testing = std.testing;
const fmt = std.fmt;
const u8fifo = std.fifo.LinearFifo(u8, .Dynamic);
const AssetsDatabase = std.ArrayList(AssetPrice);

// Constants
const name: []const u8 = "0.0.0.0";
const port = 18888;
const needle = "\n";
const message_size = 9;
const message_insert = 'I';
const message_query = 'Q';

const Queue = @import("utils").queue.Queue;

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

fn getThreadLogFile(thread_id: std.Thread.Id, allocator: std.mem.Allocator) !std.fs.File {
    const filename = try std.fmt.allocPrint(allocator, "/tmp/means-to-an-end-thread-{d}-log.txt", .{thread_id});
    defer allocator.free(filename);

    return std.fs.cwd().createFile(filename, .{ .read = true, .truncate = false }) catch |err| switch (err) {
        error.PathAlreadyExists => try std.fs.cwd().openFile(filename, .{ .mode = .read_write }),
        else => return err,
    };
}

const AssetPrice = struct {
    timestamp: i32, // In epoch
    price: i32,
};

const AssetPriceQuery = struct {
    mintime: i32, // In epoch
    maxtime: i32,
};

// Only one message received
fn messages_parse(messages: []const u8, response: *u8fifo, assets: *AssetsDatabase) !void {
    const num_msgs = messages.len / message_size;
    for (0..num_msgs) |i| {
        const start = i * message_size;
        const msg_type = messages[start];
        const first_word = std.mem.readVarInt(i32, messages[start + 1..start + 5], .big);
        const second_word = std.mem.readVarInt(i32, messages[start + 5..start + 9], .big);

        switch (msg_type) {
            message_insert => {
                try assets.append(AssetPrice{ .timestamp = first_word, .price = second_word });
            },
            message_query => {
                const query = AssetPriceQuery{ .mintime = first_word, .maxtime = second_word };
                var avg: i64 = 0;
                var count: i64 = 0;
                for (assets.items) |asset| {
                    if (asset.timestamp >= query.mintime and asset.timestamp <= query.maxtime) {
                        avg += asset.price;
                        count += 1;
                    }
                }

                // Need to convert to result to big endian
                const result = if (count == 0) 0 else @as(i32, @intCast(@divFloor(avg, count)));
                const result_big = std.mem.nativeToBig(i32, result);
                try response.write(std.mem.asBytes(&result_big));
            },
            else => {
                // Handle unknown message type
            },
        }
    }
}

fn handle_connection(connection: std.net.Server.Connection, alloc: std.mem.Allocator) void {
    const thread_id = std.Thread.getCurrentId();

    var assets = AssetsDatabase.initCapacity(alloc, 32) catch |err| {
        debug("\tERROR({d}): Failed to create assets database: {!}\n", .{ thread_id, err });
        return;
    };
    defer assets.deinit();

    const stream = connection.stream;
    defer stream.close();

    var recv_fifo = std.fifo.LinearFifo(u8, .Dynamic).init(alloc);
    defer recv_fifo.deinit();

    var send_fifo = std.fifo.LinearFifo(u8, .Dynamic).init(alloc);
    defer send_fifo.deinit();

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
        if (recv_fifo.readableLength() % message_size != 0) continue;
        const datapeek = recv_fifo.readableSlice(0);
        const num_msgs = datapeek.len / message_size;
        debug("\tTRACE({d}): processing '{}' messages\n", .{ thread_id, num_msgs });
        messages_parse(datapeek, &send_fifo, &assets) catch |err| {
            debug("\tERROR({d}): error while parsing messages: {!}\n", .{ thread_id, err });
            return;
        };

        // Send response
        const resp = send_fifo.readableSlice(0);
        if (resp.len > 0) {
            // debug("\t\tINFO({d}): sending response of size: '{d}'\n", .{ thread_id, resp.len });
            stream.writeAll(resp) catch |err| {
                debug("\t\tERROR({d}): error sendAll function {}... closing this connection\n", .{ thread_id, err });
                return;
            };
            send_fifo.discard(resp.len);
        }

        recv_fifo.discard(recv_fifo.readableLength());
    }
}

test "messages_parse inserts assets correctly and handles queries" {
    var assets = std.ArrayList(AssetPrice).init(testing.allocator);
    defer assets.deinit();

    var send_fifo = std.fifo.LinearFifo(u8, .Dynamic).init(testing.allocator);
    defer send_fifo.deinit();

    const test_messages = [_]u8{
        'I', 0, 0, 0x03, 0xE8, 0, 0, 0, 100,    // type: 'I', timestamp: 1000 (0x03E8), price: 100
        'I', 0, 0, 0x07, 0xD0, 0, 0, 0, 200,    // type: 'I', timestamp: 2000 (0x07D0), price: 200
        'I', 0, 0, 0x0B, 0xB8, 0, 0, 0, 229,    // type: 'I', timestamp: 3000 (0x0BB8), price: 229
        'Q', 0, 0, 0x03, 0xE8, 0, 0, 0x0B, 0xB8, // type: 'Q', mintime: 1000, maxtime: 3000
        'Q', 0, 0, 0x07, 0xD0, 0, 0, 0x0B, 0xB8, // type: 'Q', mintime: 2000, maxtime: 3000
        'Q', 0, 0, 0x0B, 0xB9, 0, 0, 0x0F, 0xA0  // type: 'Q', mintime: 3001, maxtime: 4000
    };

    try messages_parse(std.mem.asBytes(&test_messages), &send_fifo, &assets);

    // Test asset insertions
    try testing.expectEqual(@as(usize, 3), assets.items.len);
    try testing.expectEqual(AssetPrice{ .timestamp = 1000, .price = 100 }, assets.items[0]);
    try testing.expectEqual(AssetPrice{ .timestamp = 2000, .price = 200 }, assets.items[1]);
    try testing.expectEqual(AssetPrice{ .timestamp = 3000, .price = 229 }, assets.items[2]);

    // Test query results
    var result_buffer: [4]u8 = undefined;
    _ = send_fifo.read(&result_buffer);
    try testing.expectEqual(@as(i32, 176), std.mem.readVarInt(i32, &result_buffer, .big)); // Average of 100, 200, 229

    _ = send_fifo.read(&result_buffer);
    try testing.expectEqual(@as(i32, 214), std.mem.readVarInt(i32, &result_buffer, .big)); // Average of 200, 229

    _ = send_fifo.read(&result_buffer);
    try testing.expectEqual(@as(i32, 0), std.mem.readVarInt(i32, &result_buffer, .big)); // No prices in this range

    // Ensure no more data in the FIFO
    try testing.expectEqual(@as(usize, 0), send_fifo.readableLength());
}
