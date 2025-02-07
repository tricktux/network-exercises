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
const malformed_resp = "{\"malformed request received!!!!\"}\n";

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
    const filename = try std.fmt.allocPrint(allocator, "/tmp/prime-time-thread-{d}-log.txt", .{thread_id});
    defer allocator.free(filename);

    return std.fs.cwd().createFile(filename, .{ .read = true, .truncate = false }) catch |err| switch (err) {
        error.PathAlreadyExists => try std.fs.cwd().openFile(filename, .{ .mode = .read_write }),
        else => return err,
    };
}

fn handle_connection(connection: std.net.Server.Connection, alloc: std.mem.Allocator) void {
    const thread_id = std.Thread.getCurrentId();

    var log_file = getThreadLogFile(thread_id, alloc) catch |err| {
        debug("\tERROR({d}): Failed to create log file: {!}\n", .{ thread_id, err });
        return;
    };
    defer log_file.close();

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
        const datapeek = recv_fifo.readableSlice(0);
        var idx = std.mem.lastIndexOf(u8, datapeek, needle);
        if (idx == null) continue;
        idx.? += 1; // Include the very last message there

        log_file.writer().print("Request: {s}\n", .{datapeek}) catch {};
        // Pass along only full messages

        // Send response
        const resp = send_fifo.readableSlice(0);
        if (resp.len > 0) {
            log_file.writer().print("Response: {s}\n", .{resp}) catch {};
            // debug("\t\tINFO({d}): sending response of size: '{d}'\n", .{ thread_id, resp.len });
            stream.writeAll(resp) catch |err| {
                debug("\t\tERROR({d}): error sendAll function {}... closing this connection\n", .{ thread_id, err });
                return;
            };
        }

        send_fifo.discard(resp.len);
        recv_fifo.discard(idx.?);
    }
}
