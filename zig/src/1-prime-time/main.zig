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
const malformed_resp = "{\"method\":\"isPrime\",\"prime\":\"invalid request received!!!!\"}\n";

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

const Request = struct {
    method: []const u8,
    number: i64,
};

const JsonReqParseError = error{
    EmptyRequest,
    InvalidRequest,
    MissingMethod,
    InvalidMethod,
    MissingNumber,
    InvalidNumber,
};

fn parse_request(req: []const u8, alloc: std.mem.Allocator) !i64 {
    if (req.len == 0) return error.EmptyRequest;

    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, req, .{});
    defer parsed.deinit();

    const expected = "isPrime";

    if (parsed.value != .object) return error.InvalidRequest;

    // Sanitize method
    const method = parsed.value.object.get("method") orelse return error.MissingMethod;
    if (method != .string) return error.InvalidMethod;
    if (method.string.len != expected.len) return error.InvalidMethod;
    if (!std.mem.eql(u8, method.string[0..expected.len], expected)) return error.InvalidMethod;

    // Sanitize number
    const number = parsed.value.object.get("number") orelse return error.MissingNumber;
    if (number != .integer) return error.InvalidNumber;

    return number.integer;
}

fn is_prime(number: i64) bool {
    // less than 2 are not prime numbers
    if (number <= 1) return false;

    var i: i64 = 2;
    while (i * i <= number) : (i += 1) {
        if (@mod(number, i) == 0) return false;
    }

    return true;
}

fn processMessages(messages: []const u8, send_fifo: *u8fifo, alloc: std.mem.Allocator) !bool {
    var start: usize = 0;
    const thread_id = std.Thread.getCurrentId();
    var idx: ?usize = undefined;

    while (true) {
        idx = std.mem.indexOf(u8, messages[start..], "\n");
        if (idx == null) break;

        idx.? += start;

        // We got a full message, decode it
        const resp = try send_fifo.writableWithSize(std.mem.page_size);

        debug("\t\t\tINFO({d}): processing: '{s}', start: '{d}', end: '{d}'\n", .{ thread_id, messages[start..idx.?], start, idx.? });
        const number = parse_request(messages[start..idx.?], alloc) catch |err| {
            @memcpy(resp[0..malformed_resp.len], malformed_resp);
            debug("\t\tWARN({d}): err = '{!}', malformed request: '{s}'\n", .{ thread_id, err, messages[start..idx.?] });
            send_fifo.update(malformed_resp.len);
            return true;
        };

        // is prime?
        const prime = if (is_prime(number)) "true" else "false";
        const response = try fmt.bufPrint(resp, "{{\"method\":\"isPrime\",\"prime\":{s}}}\n", .{prime});

        debug("\t\t\tINFO({d}): response: '{s}'\n", .{ thread_id, response[0 .. response.len - 1] });
        send_fifo.update(response.len);

        // Update start and idx
        start = idx.? + 1;
        if (start >= messages.len) break;
    }

    return false;
}

fn handle_connection(connection: std.net.Server.Connection, alloc: std.mem.Allocator) void {
    const thread_id = std.Thread.getCurrentId();

    const stream = connection.stream;
    defer stream.close();

    var recv_fifo = std.fifo.LinearFifo(u8, .Dynamic).init(alloc);
    defer recv_fifo.deinit();

    var send_fifo = std.fifo.LinearFifo(u8, .Dynamic).init(alloc);
    defer send_fifo.deinit();

    var malformed = false;

    while (true) {
        debug("\tINFO({d}): waiting for some data...\n", .{thread_id});
        const data = recv_fifo.writableWithSize(std.mem.page_size) catch |err| {
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
        var idx = std.mem.lastIndexOf(u8, datapeek, needle);
        if (idx == null) continue;
        idx.? += 1;  // Include the very last message there

        // Pass along only full messages
        malformed = processMessages(datapeek[0..idx.?], &send_fifo, alloc) catch {
            debug("\t\tWARN({d}): Error while processMessages\n", .{
                thread_id,
            });
            return;
        };

        // Send response
        const resp = send_fifo.readableSlice(0);
        debug("\t\tINFO({d}): sending response of size: '{d}'\n", .{ thread_id, resp.len });
        stream.writeAll(resp) catch |err| {
            debug("\t\tERROR({d}): error sendAll function {}... closing this connection\n", .{ thread_id, err });
            return;
        };

        if (malformed) {
            debug("\tERROR({d}): malformed request received... closing this connection\n", .{thread_id});
            return; // Stop handling request
        }
        send_fifo.discard(resp.len);
        recv_fifo.discard(idx.?);
    }
}

// Make tests for the parse_request function
test "parse_request" {
    const good_request = "{\"method\": \"isPrime\", \"number\": 42}";
    const good_request2 = "{\"number\": 100000000, \"method\": \"isPrime\"}";
    const bad_request = "{\"method\": \"method\", \"number\": 42}";
    const bad_request2 = "{\"method\": \"isPrimeoieoruertert\", \"number\": 42}";
    const bad_request3 = "{\"method\": \"isPrime\", \"number\": \"42\"}";
    const bad_request4 = "{\"method\": \"isPrime\", \"number\": 42.45}";
    const bad_request5 = "";
    // Good request
    try testing.expectEqual(parse_request(good_request, testing.allocator), 42);
    try testing.expectEqual(parse_request(good_request2, testing.allocator), 100000000);
    // Bad request
    try testing.expectError(error.InvalidMethod, parse_request(bad_request, testing.allocator));
    try testing.expectError(error.InvalidMethod, parse_request(bad_request2, testing.allocator));
    try testing.expectError(error.InvalidNumber, parse_request(bad_request3, testing.allocator));
    try testing.expectError(error.InvalidNumber, parse_request(bad_request4, testing.allocator));
    try testing.expectError(error.EmptyRequest, parse_request(bad_request5, testing.allocator));
}

test "processMessages" {
    const allocator = std.testing.allocator;

    var send_fifo = u8fifo.init(allocator);
    defer send_fifo.deinit();

    // Test valid single message
    {
        const messages =
            \\{"method":"isPrime","number":7}
            \\
        ;
        const result = try processMessages(messages, &send_fifo, allocator);
        try testing.expect(!result);
        const response = send_fifo.readableSlice(0);
        try testing.expectEqualStrings(
            \\{"method":"isPrime","prime":true}
            \\
        , response);
        send_fifo.discard(response.len);
    }

    // Test valid multiple messages
    {
        const messages =
            \\{"method":"isPrime","number":4}
            \\{"method":"isPrime","number":11}
            \\
        ;
        const result = try processMessages(messages, &send_fifo, allocator);
        try testing.expect(!result);
        const response = send_fifo.readableSlice(0);
        try testing.expectEqualStrings(
            \\{"method":"isPrime","prime":false}
            \\{"method":"isPrime","prime":true}
            \\
        , response);
        send_fifo.discard(response.len);
    }

    // Test invalid message
    {
        const messages =
            \\{"method":"notIsPrime","number":7}
            \\
        ;
        const result = try processMessages(messages, &send_fifo, allocator);
        try testing.expect(result);
        const response = send_fifo.readableSlice(0);
        try testing.expectEqualStrings(malformed_resp, response);
        send_fifo.discard(response.len);
    }

    // Test mixed valid and invalid messages
    {
        const messages =
            \\{"method":"isPrime","number":2}
            \\{"invalid":"json"}
            \\{"method":"isPrime","number":9}
            \\
        ;
        const result = try processMessages(messages, &send_fifo, allocator);
        try testing.expect(result);
        const response = send_fifo.readableSlice(0);
        try testing.expectEqualStrings(
            \\{"method":"isPrime","prime":true}
            \\{"method":"isPrime","prime":"invalid request received!!!!"}
            \\
        , response);
        send_fifo.discard(response.len);
    }

    // Test complete messages followed by an incomplete one
    {
        const messages =
            \\{"method":"isPrime","number":3}
            \\{"method":"isPrime","number":6}
            \\{"method":"isPrime","number":13
        ;
        const result = try processMessages(messages, &send_fifo, allocator);
        try testing.expect(!result);
        const response = send_fifo.readableSlice(0);
        try testing.expectEqualStrings(
            \\{"method":"isPrime","prime":true}
            \\{"method":"isPrime","prime":false}
            \\
        , response);
        send_fifo.discard(response.len);

        // Simulate a second call to processMessages with the rest of the incomplete message
        // const remaining_message =
        //     \\}
        //     \\
        // ;
        // const result2 = try processMessages(remaining_message, &send_fifo, allocator);
        // try testing.expect(!result2);
        // const response2 = send_fifo.readableSlice(0);
        // try testing.expectEqualStrings(
        //     \\{"method":"isPrime","prime":true}
        //     \\
        // , response2);
        // send_fifo.discard(response2.len);
    }
}
