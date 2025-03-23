const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

// Set this to false to disable all debug prints
const enable_debug = true;

// Define a no-op function with the same signature as std.debug.print
fn noop_print(comptime fmt_: []const u8, args: anytype) void { _ = fmt_; _ = args; }

// Choose the appropriate function based on enable_debug
const debug = if (enable_debug) std.debug.print else noop_print;
const testing = std.testing;
const fmt = std.fmt;
const time = std.time;
const Thread = std.Thread;
const u8fifo = std.fifo.LinearFifo(u8, .Dynamic);
const u8boundarray = std.BoundedArray(u8, 1024);
const ClientServerHashMap = std.AutoHashMap(std.net.Stream, std.net.Stream);
const StreamFifoHashMap = std.AutoHashMap(std.net.Stream, u8fifo);

// Constants
const name: []const u8 = "0.0.0.0";
const port = 18888;
const server_name: []const u8 = "chat.protohackers.com";
const server_port = 16963;
const needle = "\n";
const kernel_backlog = 256;
const epoll_event_flags = linux.EPOLL.IN | linux.EPOLL.ET;

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
            server = addr.listen(.{
                .kernel_backlog = kernel_backlog,
                .reuse_address = true,
                .force_nonblocking = true,
            }) catch continue;

            debug("\tGot one!\n", .{});
            break;
        }
    }

    // Initialize thread pool
    const cpus = try std.Thread.getCpuCount();
    var tp: std.Thread.Pool = undefined;
    try tp.init(.{ .allocator = allocator, .n_jobs = @as(u32, @intCast(cpus)) });
    defer tp.deinit();

    var map = ConnectionHashMap.init(allocator);

    // Epoll creation
    const epollfd = try std.posix.epoll_create1(0);
    defer std.posix.close(epollfd);

    const serverfd = server.stream.handle;

    // Monitor our main proxy server
    {
        var event = linux.epoll_event{ .events = epoll_event_flags, .data = .{ .fd = serverfd } };
        try std.posix.epoll_ctl(epollfd, linux.EPOLL.CTL_ADD, serverfd, &event);
    }

    var ready_list: [kernel_backlog]linux.epoll_event = undefined;

    var ctx = Context{ .serverfd = serverfd, .epollfd = epollfd, .clientfd = undefined };

    debug("ThreadPool initialized with {} capacity\n", .{cpus});
    debug("We are listeninig baby!!!...\n", .{});
    const thread_id = std.Thread.getCurrentId();
    while (true) {
        debug("INFO({d}): waiting for a new event...\n", .{thread_id});
        // try tp.spawn(handle_connection, .{ connection, allocator });
        const ready_count = std.posix.epoll_wait(epollfd, &ready_list, -1);
        debug("INFO: got '{d}' events\n", .{ready_count});
        for (ready_list[0..ready_count]) |ready| {
            const ready_socket = ready.data.fd;
            if (ready_socket == serverfd) {
                debug("\tINFO({d}): got new connection!!!\n", .{thread_id});
                try tp.spawn(handle_connection, .{ &map, ctx, allocator });
            } else {
                ctx.clientfd = ready_socket;
                debug("\tINFO({d}): got new message!!!\n", .{thread_id});
                try tp.spawn(handle_messge, .{ &map, ctx });
            }
        }
    }
}

const ConnectionHashMap = struct {
    map: ClientServerHashMap,
    streamfifomap: StreamFifoHashMap,
    mutex: std.Thread.Mutex = .{},
    alloc: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConnectionHashMap {
        return .{
            .map = ClientServerHashMap.init(allocator),
            .streamfifomap = StreamFifoHashMap.init(allocator),
            .alloc = allocator,
        };
    }

    pub fn deinit(self: *ConnectionHashMap) void {
        var it = self.streamfifomap.iterator();
        for (it.next()) |entry| {
            entry.value.deinit();
        }
        self.map.deinit();
        self.streamfifomap.deinit();
    }

    pub fn add(self: *ConnectionHashMap, client: std.net.Stream, upstream: std.net.Stream) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.map.put(client, upstream);
        try self.streamfifomap.put(client, u8fifo.init(self.alloc));
        try self.map.put(upstream, client);
        try self.streamfifomap.put(upstream, u8fifo.init(self.alloc));
    }

    pub fn remove(self: *ConnectionHashMap, client: std.net.Stream) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // TODO: turn all of this naked returns into error.X returns
        // Get pair
        const upstream = self.map.get(client);
        if (upstream == null) return;

        // Remove client
        _ = self.map.remove(client);
        const cfkv = self.streamfifomap.fetchRemove(client);
        if (cfkv == null) return;
        cfkv.?.value.deinit();

        // Remove upstream
        _ = self.map.remove(upstream.?);
        const ufkv = self.streamfifomap.fetchRemove(upstream.?);
        if (ufkv == null) return;
        ufkv.?.value.deinit();
    }

    pub fn get_stream(self: *ConnectionHashMap, client: std.net.Stream) ?std.net.Stream {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.map.get(client);
    }

    pub fn get_fifo(self: *ConnectionHashMap, client: std.net.Stream) ?*u8fifo {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.streamfifomap.getPtr(client);
    }
};

// We don't need to differentiate between client and server
const Context = struct {
    epollfd: i32,
    serverfd: std.posix.socket_t,
    clientfd: std.posix.socket_t,
};

fn find_and_replace_boguscoin_address(msg: *u8boundarray) !void {
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
        var alphanum = false;
        while (nidx < cslice.len) {
            // Check end of address
            if (cslice[nidx] == ' ' or cslice[nidx] == '\n') break;

            // Check that is alpha numeric
            if (!std.ascii.isAlphanumeric(cslice[nidx])) alphanum = true;
            nidx += 1;
        }

        const len = nidx - idx.?;
        if (alphanum or len < boguscoin_min_len or len > boguscoin_max_len) {
            start += len; // Not supporting nested addresses
            continue;
        }

        // Now we have a valid address. Replace it.
        // Remove offset by one in case of continue branch
        try msg.replaceRange(start - 1, len, boguscoin_address);
        start += boguscoin_address.len; // Not supporting nested addresses
    }
}

fn handle_connection(map: *ConnectionHashMap, ctx: Context, alloc: std.mem.Allocator) void {
    const thread_id = std.Thread.getCurrentId();

    const client_socket = std.posix.accept(ctx.serverfd, null, null, std.posix.SOCK.NONBLOCK | std.posix.SOCK.CLOEXEC) catch |err| {
        debug("\tERROR({d}): error while accepting connection: {!}\n", .{ thread_id, err });
        return;
    };
    errdefer std.posix.close(client_socket);
    var event = linux.epoll_event{ .events = epoll_event_flags, .data = .{ .fd = client_socket } };
    std.posix.epoll_ctl(ctx.epollfd, linux.EPOLL.CTL_ADD, client_socket, &event) catch |err| {
        debug("\tERROR({d}): error while adding client to epoll: {!}\n", .{ thread_id, err });
        return;
    };
    const client = std.net.Stream{ .handle = client_socket };

    // Make upstream connection
    var upstream: std.net.Stream = undefined;
    {
        const list = std.net.getAddressList(alloc, server_name, server_port) catch |err| {
            debug("\tERROR({d}): error while getting address list: {!}\n", .{ thread_id, err });
            return;
        };
        defer list.deinit();

        if (list.addrs.len == 0) {
            debug("\tERROR({d}): no address found\n", .{thread_id});
            return;
        }

        var found = false;
        for (list.addrs) |addr| {
            const sock_flags = std.posix.SOCK.STREAM |
                (if (builtin.os.tag == .windows) 0 else std.posix.SOCK.CLOEXEC);
            const sockfd = std.posix.socket(addr.any.family, sock_flags, std.posix.IPPROTO.TCP) catch {
                debug("\t\tERROR({d}): error while creating socket\n", .{thread_id});
                continue;
            };
            errdefer std.net.Stream.close(.{ .handle = sockfd });

            std.posix.connect(sockfd, &addr.any, addr.getOsSockLen()) catch |err| {
                debug("\t\tERROR({d}): error while connecting to upstream: {!}\n", .{thread_id, err});
                continue;
            };

            // Avoid waiting for connect async
            // set socket nonblocking
            _ = std.posix.fcntl(sockfd, std.posix.F.SETFL, sock_flags | std.posix.SOCK.NONBLOCK) catch |err| {
                debug("\t\tERROR({d}): error while setting socket nonblocking: {!}\n", .{thread_id, err});
                continue;
            };

            upstream = std.net.Stream{ .handle = sockfd };
            found = true;
            break;
        }

        if (found == false) {
            debug("\tERROR({d}): error while connecting to upstream\n", .{thread_id});
            return;
        }
    }

    var event2 = linux.epoll_event{ .events = epoll_event_flags, .data = .{ .fd = upstream.handle } };
    std.posix.epoll_ctl(ctx.epollfd, linux.EPOLL.CTL_ADD, upstream.handle, &event2) catch |err| {
        debug("\tERROR({d}): error while adding upstream to epoll: {!}\n", .{ thread_id, err });
        return;
    };
    debug("\tINFO({d}): new client: {d}, upstream: {d} pair\n", .{ thread_id, client.handle, upstream.handle });
    map.add(client, upstream) catch |err| {
        debug("\tERROR({d}): error while adding to map: {!}\n", .{ thread_id, err });
        return;
    };
}

fn handle_messge(map: *ConnectionHashMap, ctx: Context) void {
    const thread_id = std.Thread.getCurrentId();

    const client = std.net.Stream{ .handle = ctx.clientfd };
    const upstream = map.get_stream(client);
    if (upstream == null) {
        debug("ERROR: no upstream found\n", .{});
        return;
    }

    var recv_fifo = map.get_fifo(client);
    if (recv_fifo == null) {
        debug("ERROR: no fifo found\n", .{});
        return;
    }

    debug("\tINFO({d}): client: {d}, upstream: {d} pair\n", .{ thread_id, client.handle, upstream.?.handle });
    var bytes: usize = 0;
    while (true) {
        const buf = recv_fifo.?.writableWithSize(2048) catch |err| {
            debug("\tERROR({d}): error while recv_fifo.writableWithSize: {!}\n", .{ thread_id, err });
            return;
        };
        bytes = client.read(buf) catch |err| {
            switch (err) {
                error.WouldBlock => break,
                else => {
                    debug("\tERROR: error while reading from client: {!}\n", .{err});
                    return;
                },
            }
        };
        if (bytes == 0) break;
        recv_fifo.?.update(bytes);
    }

    if (bytes == 0) {
        debug("WARN: Client closing this connection\n", .{});
        map.remove(client) catch |err| {
            debug("ERROR: error while removing from map: {!}\n", .{err});
        };
        std.posix.epoll_ctl(ctx.epollfd, linux.EPOLL.CTL_DEL, client.handle, null) catch |err| {
            debug("ERROR: error while removing client from epoll: {!}\n", .{err});
        };
        std.posix.epoll_ctl(ctx.epollfd, linux.EPOLL.CTL_DEL, upstream.?.handle, null) catch |err| {
            debug("ERROR: error while removing upstream from epoll: {!}\n", .{err});
        };

        std.posix.close(client.handle);
        std.posix.close(upstream.?.handle);
        return;
    }

    const datapeek = recv_fifo.?.readableSlice(0);
    const idx = std.mem.lastIndexOf(u8, datapeek, needle);
    if (idx == null) {
        debug("\tWARN: no full message found\n", .{});
        return;
    }

    debug("\tINFO({d}): received full message: {s}\n", .{ thread_id, datapeek });
    defer recv_fifo.?.discard(recv_fifo.?.readableLength());

    var msg_buffer = u8boundarray.fromSlice(datapeek) catch |err| {
        debug("ERROR: error while appending to msg_buffer: {!}\n", .{err});
        return;
    };

    find_and_replace_boguscoin_address(&msg_buffer) catch |err| {
        debug("ERROR: error while finding and replacing Boguscoin address: {!}\n", .{err});
        return;
    };

    debug("\tINFO({d}): sending message: {s}\n", .{ thread_id, msg_buffer.slice() });
    upstream.?.writeAll(msg_buffer.constSlice()) catch |err| {
        debug("ERROR: error while writing to upstream: {!}\n", .{err});
        return;
    };
}

test "find_and_replace_boguscoin_address" {
    const boguscoin_replacement = "7YWHMfk9JZe0LM0g1ZauHuiSxhI";

    // Test: Empty message
    {
        var msg = try u8boundarray.init(0);
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "", msg.slice());
    }

    // Test: Message with no Boguscoin address
    {
        var msg = try u8boundarray.fromSlice("This message has no Boguscoin address");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "This message has no Boguscoin address", msg.slice());
    }

    // Test: Message with a '7' but no valid address
    {
        var msg = try u8boundarray.fromSlice("This message has a 7 but no address");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "This message has a 7 but no address", msg.slice());
    }

    // Test: Valid address at the beginning
    {
        const address = "7F1u3wSD5RbOHQmupo9nx4TnhQ";
        var msg = try u8boundarray.fromSlice(address ++ " is a Boguscoin address");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, boguscoin_replacement ++ " is a Boguscoin address", msg.slice());
    }

    // Test: Valid address in the middle
    {
        const address = "7iKDZEwPZSqIvDnHvVN2r0hUWXD5rHX";
        var msg = try u8boundarray.fromSlice("The address " ++ address ++ " is valid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address " ++ boguscoin_replacement ++ " is valid", msg.slice());
    }

    // Test: Valid address at the end
    {
        const address = "7LOrwbDlS8NujgjddyogWgIM93MV5N2VR";
        var msg = try u8boundarray.fromSlice("The address is " ++ address);
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address is " ++ boguscoin_replacement, msg.slice());
    }

    // Test: Valid address followed by newline
    {
        const address = "7adNeSwJkMakpEcln9HEtthSRtxdmEHOT8T";
        var msg = try u8boundarray.fromSlice("The address is " ++ address ++ "\nAnd this is a new line");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address is " ++ boguscoin_replacement ++ "\nAnd this is a new line", msg.slice());
    }

    // Test: Address too short
    {
        var msg = try u8boundarray.fromSlice("The address 7short is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address 7short is invalid", msg.slice());
    }

    // Test: Address too long
    {
        var msg = try u8boundarray.fromSlice("The address 7thisisaverylongaddressmorethan35chars is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address 7thisisaverylongaddressmorethan35chars is invalid", msg.slice());
    }

    // Test: Address doesn't start with 7
    {
        var msg = try u8boundarray.fromSlice("The address 8F1u3wSD5RbOHQmupo9nx4TnhQ is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address 8F1u3wSD5RbOHQmupo9nx4TnhQ is invalid", msg.slice());
    }

    // Test: Multiple addresses (only first should be replaced)
    {
        const address1 = "7F1u3wSD5RbOHQmupo9nx4TnhQ";
        const address2 = "7iKDZEwPZSqIvDnHvVN2r0hUWXD5rHX";
        var msg = try u8boundarray.fromSlice("The addresses " ++ address1 ++ " and " ++ address2 ++ " are valid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The addresses " ++ boguscoin_replacement ++ " and " ++ boguscoin_replacement ++ " are valid", msg.slice());
    }

    // Test: Address not separated by spaces
    {
        const address = "7F1u3wSD5RbOHQmupo9nx4TnhQ";
        var msg = try u8boundarray.fromSlice("The address" ++ address ++ "is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address" ++ address ++ "is invalid", msg.slice());
    }

    // Test: Address with non-alphanumeric characters
    {
        var msg = try u8boundarray.fromSlice("The address 7F1u3wSD5RbOHQmupo9nx4TnhQ! is invalid");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "The address 7F1u3wSD5RbOHQmupo9nx4TnhQ! is invalid", msg.slice());
    }

    // Test from actual data
    {
        var msg = try u8boundarray.fromSlice("Please pay the ticket price of 15 Boguscoins to one of these addresses: 79XTJ0kjDSj74S3JzaPwG6H99q3D3gIbx 7KgQ43NyUuVFoCYoUL7hffAFQk8L2H 7fCg2CEiztOqwPAg8F9kdoGdVgzT4ee0A");
        try find_and_replace_boguscoin_address(&msg);
        try testing.expectEqualSlices(u8, "Please pay the ticket price of 15 Boguscoins to one of these addresses: 7YWHMfk9JZe0LM0g1ZauHuiSxhI 7YWHMfk9JZe0LM0g1ZauHuiSxhI 7YWHMfk9JZe0LM0g1ZauHuiSxhI", msg.slice());
    }
}
