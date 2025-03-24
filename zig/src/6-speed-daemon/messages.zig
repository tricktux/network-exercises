const std = @import("std");
const testing = std.testing;

const MessageBoundedArray = std.BoundedArray(Message, 64);

const Type = enum(u8) {
    ErrorM = 0x10,
    Plate = 0x20,
    Ticket = 0x21,
    WantHeartbeat = 0x40,
    Hearbeat = 0x41,
    IAmCamera = 0x80,
    IAmDispatcher = 0x81,
};

const ErrorM = struct {
    msg: []const u8,
};

const Plate = struct {
    plate: []const u8,
    timestamp: u32,
};

const Ticket = struct {
    plate: []const u8,
    road: u16,
    mile1: u16,
    timestamp1: u32,
    mile2: u16,
    timestamp2: u32,
    speed: u16,
};

const WantHeartbeat = struct { interval: u32 };

const Heartbeat = struct {};

const IAmCamera = struct {
    road: u16,
    mile: u16,
    limit: u16,
};

const IAmDispatcher = struct {
    numroads: u16,
    roads: []u16,
};

// TODO: Add function to convert unix epoch timestamp to date
const Message = struct {
    type: Type,
    data: union(enum) {
        errorm: ErrorM,
        plate: Plate,
        ticket: Ticket,
        want_heartbeat: WantHeartbeat,
        heartbeat: Heartbeat,
        camera: IAmCamera,
        dispatcher: IAmDispatcher,
    },

    pub fn initError(err: []const u8) Message {
        return Message{ .type = Type.ErrorM, .data = .errorm{ .msg = err } };
    }

    pub fn initPlate(plate: Plate) Message {
        return Message{
            .type = Type.Plate,
            .data = .{ .plate = plate },
        };
    }

    pub fn initTicket(ticket: Ticket) Message {
        return Message{
            .type = Type.Ticket,
            .data = .{ .ticket = ticket },
        };
    }

    pub fn initWantHeartbeat(interval: u32) Message {
        return Message{
            .type = Type.WantHeartbeat,
            .data = .{ .want_heartbeat = .{ .interval = interval } },
        };
    }

    pub fn initHeartbeat() Message {
        return Message{ .type = Type.Hearbeat, .data = .heartbeat{} };
    }

    pub fn initCamera(camera: IAmCamera) Message {
        return Message{
            .type = Type.IAmCamera,
            .data = .{ .camera = camera },
        };
    }

    pub fn initDispatcher(dispatcher: IAmDispatcher) Message {
        return Message{
            .type = Type.IAmDispatcher,
            .data = .{ .dispatcher = dispatcher },
        };
    }
};

const DecodeError = error{
    InvalidMessageType,
    NotEnoughBytes,
};

// TODO: Add return of number of bytes processed
pub fn decode(buf: []const u8, array: *MessageBoundedArray) !u16 {
    if (buf.len < 2) return error.NotEnoughBytes;

    var start: u16 = 0;
    var len: u16 = 0;

    while (start < buf.len) {
        const mtype: Type = @enumFromInt(buf[start]);
        switch (mtype) {
            Type.Plate => {
                if (buf.len < 7) return error.NotEnoughBytes;

                std.log.info("(decode): Decoding plate message", .{});
                const platelen = buf[start + 1];
                const platestart = start + 2;
                const plateend = platestart + platelen;
                if (buf.len < plateend) return error.NotEnoughBytes;
                // TODO: Transfer ownership to the message?
                const plate: []const u8 = buf[platestart..plateend];

                const timestampstart = platelen + 1;
                const timestampend = platelen + 1 + 4;
                if (buf.len < timestampend) return error.NotEnoughBytes;
                const timestamp: u32 = std.mem.readVarInt(u32, buf[timestampstart..timestampend], .big);
                const platem = Plate{
                    .plate = plate,
                    .timestamp = timestamp,
                };
                std.log.debug("(decode): plate: {s}, timestamp: {d}", .{ plate, timestamp });
                const m = Message.initPlate(platem);
                try array.append(m);
                len += timestampend - start;
                start = timestampend;
                std.log.debug("(decode): start: {d}, len: {d}", .{ start, len });
            },
            else => return error.InvalidMessageType,
        }
    }

    return len;
}

test "decode - empty buffer returns error" {
    var array = try MessageBoundedArray.init(0);

    const result = decode(&[_]u8{}, &array);
    try testing.expectError(error.NotEnoughBytes, result);
    try testing.expectEqual(@as(usize, 0), array.len);
}

test "decode - buffer with only type returns error" {
    var array = try MessageBoundedArray.init(0);

    const buf = [_]u8{@intFromEnum(Type.Plate)};
    const result = decode(&buf, &array);
    try testing.expectError(error.NotEnoughBytes, result);
}

test "decode - valid Plate message" {
    var array = try MessageBoundedArray.init(0);

    // Create a valid Plate message buffer
    const plate_str = "ABC123";
    const timestamp: u32 = 12345;

    var buf = [_]u8{
        @intFromEnum(Type.Plate), // Message type
        plate_str.len, // Plate length
    };

    var full_buf = std.ArrayList(u8).init(testing.allocator);
    defer full_buf.deinit();
    try full_buf.appendSlice(&buf);
    try full_buf.appendSlice(plate_str);

    // Add timestamp in big endian
    var ts_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &ts_bytes, timestamp, .big);
    try full_buf.appendSlice(&ts_bytes);

    const bytes_consumed = try decode(full_buf.items, &array);

    // Check results
    try testing.expectEqual(@as(u16, @intCast(full_buf.items.len)), bytes_consumed);
    try testing.expectEqual(@as(usize, 1), array.len);

    const msg = array.buffer[0];
    try testing.expectEqual(Type.Plate, msg.type);
    try testing.expectEqualStrings(plate_str, msg.data.plate.plate);
    try testing.expectEqual(timestamp, msg.data.plate.timestamp);
}

test "decode - insufficient bytes for plate data" {
    var array = try MessageBoundedArray.init(0);

    // Plate message with insufficient data
    var buf = [_]u8{
        @intFromEnum(Type.Plate),
        6, // Plate length
        'A', 'B', 'C', // Only 3 bytes of a 6-byte plate
    };

    const result = decode(&buf, &array);
    try testing.expectError(error.NotEnoughBytes, result);
}

test "decode - insufficient bytes for timestamp" {
    var array = try MessageBoundedArray.init(0);

    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try buf.append(@intFromEnum(Type.Plate));
    try buf.append(3); // Plate length
    try buf.appendSlice("ABC"); // Complete plate
    try buf.appendSlice(&[_]u8{ 0, 0 }); // Incomplete timestamp (should be 4 bytes)

    const result = decode(buf.items, &array);
    try testing.expectError(error.NotEnoughBytes, result);
}

test "decode - plate messages" {
    var array = try MessageBoundedArray.init(0);

    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    // First Plate message
    const plate1 = "ABC123";
    const timestamp1: u32 = 12345;

    try buf.append(@intFromEnum(Type.Plate));
    try buf.append(plate1.len);
    try buf.appendSlice(plate1);

    var ts_bytes1: [4]u8 = undefined;
    std.mem.writeInt(u32, &ts_bytes1, timestamp1, .big);
    try buf.appendSlice(&ts_bytes1);

    // Second Plate message
    const plate2 = "XYZ789";
    const timestamp2: u32 = 67890;

    try buf.append(@intFromEnum(Type.Plate));
    try buf.append(plate2.len);
    try buf.appendSlice(plate2);

    var ts_bytes2: [4]u8 = undefined;
    std.mem.writeInt(u32, &ts_bytes2, timestamp2, .big);
    try buf.appendSlice(&ts_bytes2);

    const bytes_consumed = try decode(buf.items, &array);

    try testing.expectEqual(@as(u16, @intCast(buf.items.len)), bytes_consumed);
    try testing.expectEqual(@as(usize, 2), array.len);

    // Check first message
    const msg1 = array.buffer[0];
    try testing.expectEqual(Type.Plate, msg1.type);
    try testing.expectEqualStrings(plate1, msg1.data.plate.plate);
    try testing.expectEqual(timestamp1, msg1.data.plate.timestamp);

    // Check second message
    const msg2 = array.buffer[1];
    try testing.expectEqual(Type.Plate, msg2.type);
    try testing.expectEqualStrings(plate2, msg2.data.plate.plate);
    try testing.expectEqual(timestamp2, msg2.data.plate.timestamp);
}
