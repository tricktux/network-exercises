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
const server_name: []const u8 = "chat.protohackers.com:16963";
const server_port = 16963;
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

fn find_and_replace_boguscoin_address(msg: *std.BoundedArray(u8, 1024)) !void {
    if (msg.len == 0) return;

    const boguscoin_start = "7";
    const boguscoin_max_len = 35;
    const boguscoin_min_len = 26;
    const boguscoin_address = "7YWHMfk9JZe0LM0g1ZauHuiSxhI";

    var start: usize = 0;
    while (start < msg.len) {
        const cslice = msg.constSlice()[start..];
        const idx = std.mem.indexOf(u8, cslice, boguscoin_start);
        if (idx == null) return;

        start += idx.? + 1;
        // Discard if too short
        if (idx.? + boguscoin_min_len > cslice.len) return;
        // Check start of address
        if (idx.? != 0 and cslice[idx.? - 1] != ' ') continue;

        // Start walking the address
        var nidx = idx.?;
        var alpanum = false;
        while (nidx < cslice.len) {
            // Check end of address
            if (cslice[nidx] == ' ' or cslice[nidx] == '\n') break;

            // Check that is alpha numeric
            if (!std.ascii.isAlphanumeric(cslice[nidx])) {
                alpanum = true;
                break;
            }
            nidx += 1;
        }

        if (alpanum) continue;
        const len = nidx - idx.?;
        if (len < boguscoin_min_len or len > boguscoin_max_len) continue;

        // Now we have a valid address. Replace it.
        // Remove offset by one in case of continue branch
        try msg.replaceRange(start - 1, len, boguscoin_address);
        start += len + 1;  // Not supporting nested addresses
    }
}

fn handle_connection(connection: std.net.Server.Connection, alloc: std.mem.Allocator) void {
    const thread_id = std.Thread.getCurrentId();

    const stream = connection.stream;
    defer stream.close();

    var recv_fifo = std.fifo.LinearFifo(u8, .Dynamic).init(alloc);
    defer recv_fifo.deinit();

    var msg_buffer = std.BoundedArray(u8, 1024).init(0) catch |err| {
        debug("\tERROR({d}): error while initializing msg_buffer: {!}\n", .{ thread_id, err });
        return;
    };

    // Make upstream connection
    const upstream = std.net.tcpConnectToHost(alloc, server_name, server_port) catch |err| {
        debug("\tERROR({d}): error while connecting to upstream: {!}\n", .{ thread_id, err });
        return;
    };
    defer upstream.close();

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
        _ = msg;

        // TODO: search and replace bogus address
        // TODO: send to upstream
    }
}

test "find_and_replace_boguscoin_address" {
    const boguscoin_replacement = "7YWHMfk9JZe0LM0g1ZauHuiSxhI";

    // Test: Empty message
    {
        var msg = try std.BoundedArray(u8, 1024).init(0);
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "", msg.slice());
    }

    // Test: Message with no Boguscoin address
    {
        var msg = try std.BoundedArray(u8, 1024).fromSlice("This message has no Boguscoin address");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "This message has no Boguscoin address", msg.slice());
    }

    // Test: Message with a '7' but no valid address
    {
        var msg = try std.BoundedArray(u8, 1024).fromSlice("This message has a 7 but no address");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "This message has a 7 but no address", msg.slice());
    }

    // Test: Valid address at the beginning
    {
        const address = "7F1u3wSD5RbOHQmupo9nx4TnhQ";
        var msg = try std.BoundedArray(u8, 1024).fromSlice(address ++ " is a Boguscoin address");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, boguscoin_replacement ++ " is a Boguscoin address", msg.slice());
    }

    // Test: Valid address in the middle
    {
        const address = "7iKDZEwPZSqIvDnHvVN2r0hUWXD5rHX";
        var msg = try std.BoundedArray(u8, 1024).fromSlice("The address " ++ address ++ " is valid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address " ++ boguscoin_replacement ++ " is valid", msg.slice());
    }

    // Test: Valid address at the end
    {
        const address = "7LOrwbDlS8NujgjddyogWgIM93MV5N2VR";
        var msg = try std.BoundedArray(u8, 1024).fromSlice("The address is " ++ address);
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address is " ++ boguscoin_replacement, msg.slice());
    }

    // Test: Valid address followed by newline
    {
        const address = "7adNeSwJkMakpEcln9HEtthSRtxdmEHOT8T";
        var msg = try std.BoundedArray(u8, 1024).fromSlice("The address is " ++ address ++ "\nAnd this is a new line");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address is " ++ boguscoin_replacement ++ "\nAnd this is a new line", msg.slice());
    }

    // Test: Address too short
    {
        var msg = try std.BoundedArray(u8, 1024).fromSlice("The address 7short is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address 7short is invalid", msg.slice());
    }

    // Test: Address too long
    {
        var msg = try std.BoundedArray(u8, 1024).fromSlice("The address 7thisisaverylongaddressmorethan35chars is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address 7thisisaverylongaddressmorethan35chars is invalid", msg.slice());
    }

    // Test: Address doesn't start with 7
    {
        var msg = try std.BoundedArray(u8, 1024).fromSlice("The address 8F1u3wSD5RbOHQmupo9nx4TnhQ is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address 8F1u3wSD5RbOHQmupo9nx4TnhQ is invalid", msg.slice());
    }

    // Test: Multiple addresses (only first should be replaced)
    {
        const address1 = "7F1u3wSD5RbOHQmupo9nx4TnhQ";
        const address2 = "7iKDZEwPZSqIvDnHvVN2r0hUWXD5rHX";
        var msg = try std.BoundedArray(u8, 1024).fromSlice("The addresses " ++ address1 ++ " and " ++ address2 ++ " are valid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The addresses " ++ boguscoin_replacement ++ " and " ++ boguscoin_replacement ++ " are valid", msg.slice());
    }

    // Test: Address not separated by spaces
    {
        const address = "7F1u3wSD5RbOHQmupo9nx4TnhQ";
        var msg = try std.BoundedArray(u8, 1024).fromSlice("The address" ++ address ++ "is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address" ++ address ++ "is invalid", msg.slice());
    }

    // Test: Address with non-alphanumeric characters
    {
        var msg = try std.BoundedArray(u8, 1024).fromSlice("The address 7F1u3wSD5RbOHQmupo9nx4TnhQ! is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address 7F1u3wSD5RbOHQmupo9nx4TnhQ! is invalid", msg.slice());
    }
}
