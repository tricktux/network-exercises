const std = @import("std");
const linux = std.os.linux;
const debug = std.debug.print;
const testing = std.testing;
const fmt = std.fmt.format;

// Constants
const name: []const u8 = "0.0.0.0";
const port = 18888;
const buff_size = 4096;
const needle = "\n";

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
    while (true) {
        debug("waiting for a new connection...\n", .{});
        const connection = try server.accept();
        debug("got new connection!!!\n", .{});
        try tp.spawn(handle_connection, .{ connection, allocator });
    }
}

const Request = struct {
    method: []const u8,
    number: i64,
};

const ParseError = error{
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

fn handle_connection(connection: std.net.Server.Connection, alloc: std.mem.Allocator) void {
    const stream = connection.stream;
    defer stream.close();

    var recvqu = Queue.init() catch {
        debug("\tERROR: Failed to allocate recvqu memory", .{});
        return;
    };
    defer recvqu.deinit();

    var sendqu = Queue.init() catch {
        debug("\tERROR: Failed to allocate sendqu memory", .{});
        return;
    };
    defer sendqu.deinit();

    var malformed = false;
    var buf: [128]u8 = undefined;

    while (true) {
        debug("\twaiting for some data...\n", .{});
        const data = recvqu.get_writable_data();
        const bytes = stream.read(data) catch |err| {
            debug("\tERROR: error {}... closing this connection\n", .{err});
            return;
        };
        if (bytes == 0) {
            debug("\tClient closing this connection\n", .{});
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
            // We got a full message, decode it
            const number = parse_request(dataall[start..idx.?], alloc) catch {
                sendqu.push("{\"method\":\"isPrime\",\"prime\":\"invalid request received!!!!\"}\n") catch {
                    debug("\tERROR: Failed to push_ex", .{});
                    return;
                };
                malformed = true;
                break;
            };

            // is prime?
            const prime = if (is_prime(number)) "true" else "false";
            const resp = std.fmt.bufPrint(&buf, "{{\"method\":\"isPrime\",\"prime\":{s}}}\n", .{prime}) catch {
                debug("\tERROR: Failed to format response", .{});
                return;
            };

            sendqu.push(resp) catch {
                debug("\tERROR: Failed to push_ex", .{});
                return;
            };

            // Update start and idx
            start = idx.? + 1;
            idx = std.mem.indexOf(u8, dataall[start..], needle);
            if (idx == null) break; // No more messages to process
        }

        // Send response
        const resp = sendqu.pop();
        stream.writeAll(resp) catch |err| {
            debug("\tERROR: error sendAll function {}... closing this connection\n", .{err});
            return;
        };

        if (malformed) return; // Stop handling request
    }
}
