const std = @import("std");
const builtin = @import("builtin");

pub var log_file: ?std.fs.File = null;
pub var mutex = std.Thread.Mutex{};
pub var buf: [2046]u8 = undefined;

// TODO: pass log full path here
pub fn init() !void {
    if (log_file != null) return;

    const timestamp = std.time.timestamp();
    const filename = try std.fmt.bufPrint(&buf, "/tmp/client_log_{d}.txt", .{timestamp});

    log_file = try std.fs.cwd().createFile(filename, .{});
    try log_file.?.writer().print("=== Log started at timestamp {d} ===\n", .{timestamp});
}

pub fn deinit() void {
    if (log_file) |file| {
        file.close();
        log_file = null;
    }
}

// Custom log handler that writes to both stderr and file with timestamps
pub fn customLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Ignore all non-error logging from sources other than
    // .my_project, .nice_library and the default
    const scope_prefix = "(" ++ switch (scope) {
        .my_project, .nice_library, std.log.default_log_scope => @tagName(scope),
        else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
            @tagName(scope)
        else
            return,
    } ++ "): ";

    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;

    // Write to stderr
    // const stderr = std.io.getStdErr().writer();
    // stderr.print(prefix ++ format ++ "\n", args) catch {};

    // Write to log file if open
    if (log_file) |file| {
        mutex.lock();
        defer mutex.unlock();

        // Get current timestamp with millisecond precision
        const nano_timestamp = std.time.nanoTimestamp();
        const seconds = @divFloor(nano_timestamp, std.time.ns_per_s);
        const milliseconds = @divFloor(@mod(nano_timestamp, std.time.ns_per_s), std.time.ns_per_ms);

        // Format the log message
        const formatted_msg = std.fmt.bufPrint(&buf, prefix ++ format, args) catch {
            // If formatting fails, still try to log something
            file.writer().print("[{d}.{d:0>3}] ERROR formatting log message\n", .{seconds, milliseconds}) catch {};
            return;
        };

        // Write with timestamp including milliseconds
        file.writer().print("[{d}.{d:0>3}] {s}\n", .{ seconds, milliseconds, formatted_msg }) catch {};
    }
}
