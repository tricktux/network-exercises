const std = @import("std");
const testing = std.testing;

const MessageBoundedArray = std.BoundedArray(Message, 64);

const Type = enum(u8) {
    ErrorM = 0x10,
    Plate = 0x20,
    Ticket = 0x21,
    WantHeartbeat = 0x40,
    Heartbeat = 0x41,
    IAmCamera = 0x80,
    IAmDispatcher = 0x81,
    _,
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
    roads: std.ArrayList(u16),
};

// TODO: Add function to convert unix epoch timestamp to date
// TODO: Call deinit
// TODO: Add function that returns binary representation
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
        return Message{ .type = Type.Heartbeat, .data = .heartbeat{} };
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

    pub fn deinit(self: *Message) void {
        switch (self.type) {
            Type.IAmDispatcher => {
                self.data.dispatcher.roads.deinit();
            },
            else => {},
        }
    }
};

const DecodeError = error{
    InvalidMessageType,
    NotEnoughBytes,
};

fn decode_u32(buf: []const u8) !u32 {
    if (buf.len < 4) return error.NotEnoughBytes;
    return std.mem.readVarInt(u32, buf, .big);
}

fn decode_u16(buf: []const u8) !u16 {
    if (buf.len < 2) return error.NotEnoughBytes;
    return std.mem.readVarInt(u16, buf, .big);
}

pub fn decode(buf: []const u8, array: *MessageBoundedArray, alloc: std.mem.Allocator) !u16 {
    if (buf.len < 2) return error.NotEnoughBytes;

    var start: u16 = 0;
    var len: u16 = 0;

    while (start < buf.len) {
        const mtype: Type = @enumFromInt(buf[start]);
        switch (mtype) {
            Type.Plate => {
                if (buf.len - start < 7) return error.NotEnoughBytes;

                std.log.info("(decode): Decoding plate message", .{});
                const platelen = buf[start + 1];
                const platestart = start + 2;
                const plateend = platestart + platelen;
                if (buf.len < plateend) break;
                // TODO: Transfer ownership to the message?
                const plate: []const u8 = buf[platestart..plateend];

                const timestampstart = plateend;
                const timestampend = timestampstart + 4;
                if (buf.len < timestampend) break;
                const timestamp: u32 = try decode_u32(buf[timestampstart..timestampend]);
                len += timestampend - start;
                const platem = Plate{
                    .plate = plate,
                    .timestamp = timestamp,
                };
                std.log.debug("(decode): plate: {s}, timestamp: {d}", .{ plate, timestamp });
                const m = Message.initPlate(platem);
                try array.append(m);
            },
            Type.WantHeartbeat => {
                if (buf.len - start < 3) return error.NotEnoughBytes;

                std.log.info("(decode): Decoding want-heartbeat message", .{});
                const intervalstart = start + 1;
                const intervalend = intervalstart + 4;
                if (buf.len < intervalend) break;
                const interval: u32 = try decode_u32(buf[intervalstart..intervalend]);
                len += intervalend - start;
                std.log.debug("(decode): interval: {d}", .{interval});
                const m = Message.initWantHeartbeat(interval);
                try array.append(m);
            },
            Type.IAmCamera => {
                if (buf.len - start < 7) return error.NotEnoughBytes;

                std.log.info("(decode): Decoding camera id message", .{});
                const roadstart = start + 1;
                const roadend = roadstart + 2;
                const road: u16 = try decode_u16(buf[roadstart..roadend]);
                const milestart = roadend;
                const mileend = milestart + 2;
                const mile: u16 = try decode_u16(buf[milestart..mileend]);
                const limitstart = mileend;
                const limitend = limitstart + 2;
                const limit: u16 = try decode_u16(buf[limitstart..limitend]);
                len += limitend - start;
                const m = Message.initCamera(.{ .road = road, .mile = mile, .limit = limit });
                std.log.debug("(decode): road: {d}, mile: {d}, limit: {d}", .{ road, mile, limit });
                try array.append(m);
            },
            Type.IAmDispatcher => {
                if (buf.len - start < 3) return error.NotEnoughBytes;
                std.log.info("(decode): Decoding dispatcher message", .{});
                const numroads: u8 = buf[start + 1];
                if (buf.len < numroads * 2 + 1) return error.NotEnoughBytes;
                var roadsstart = start + 2;
                var roads = try std.ArrayList(u16).initCapacity(alloc, numroads);
                var i: u8 = 0;
                while (i < numroads) {
                    const r = try decode_u16(buf[roadsstart .. roadsstart + 2]);
                    try roads.append(r);
                    roadsstart += 2;
                    i += 1;
                }
                const m = Message.initDispatcher(.{ .numroads = numroads, .roads = roads });
                len += numroads * 2 + 2 - start;
                std.log.debug("(decode): numroads: {d}", .{numroads});
                try array.append(m);
            },
            else => return error.InvalidMessageType,
        }
        start += len;
        std.debug.print("(decode): start: {d}, len: {d}, buf.len: {d}\n", .{ start, len, buf.len });
        std.log.debug("(decode): start: {d}, len: {d}", .{ start, len });
    }

    return len;
}

test "decode - empty buffer returns error" {
    var array = try MessageBoundedArray.init(0);

    const result = decode(&[_]u8{}, &array, std.testing.allocator);
    try testing.expectError(error.NotEnoughBytes, result);
    try testing.expectEqual(@as(usize, 0), array.len);
    for (&array.buffer) |*msg| msg.deinit();
}

test "decode - buffer with only type returns error" {
    var array = try MessageBoundedArray.init(0);

    const buf = [_]u8{@intFromEnum(Type.Plate)};
    const result = decode(&buf, &array, std.testing.allocator);
    try testing.expectError(error.NotEnoughBytes, result);
    for (&array.buffer) |*msg| msg.deinit();
}

test "decode - valid Plate message" {
    var array = try MessageBoundedArray.init(0);

    // Create a valid Plate message buffer
    const plate_str = "ABC123";
    const timestamp: u32 = 12345;

    var full_buf = std.ArrayList(u8).init(testing.allocator);
    defer full_buf.deinit();
    try full_buf.append(@intFromEnum(Type.Plate));
    try full_buf.append(plate_str.len);
    try full_buf.appendSlice(plate_str);

    // Add timestamp in big endian
    var ts_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &ts_bytes, timestamp, .big);
    try full_buf.appendSlice(&ts_bytes);

    const bytes_consumed = try decode(full_buf.items, &array, std.testing.allocator);

    // Check results
    try testing.expectEqual(@as(u16, @intCast(full_buf.items.len)), bytes_consumed);
    try testing.expectEqual(@as(usize, 1), array.len);

    const msg = array.buffer[0];
    try testing.expectEqual(Type.Plate, msg.type);
    try testing.expectEqualStrings(plate_str, msg.data.plate.plate);
    try testing.expectEqual(timestamp, msg.data.plate.timestamp);
    for (&array.buffer) |*msgs| msgs.deinit();
}

test "decode - insufficient bytes for plate data" {
    var array = try MessageBoundedArray.init(0);

    // Plate message with insufficient data
    var buf = [_]u8{
        @intFromEnum(Type.Plate),
        6, // Plate length
        'A', 'B', 'C', // Only 3 bytes of a 6-byte plate
    };

    const result = decode(&buf, &array, std.testing.allocator);
    try testing.expectError(error.NotEnoughBytes, result);
    for (&array.buffer) |*msg| msg.deinit();
}

test "decode - insufficient bytes for timestamp" {
    var array = try MessageBoundedArray.init(0);

    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try buf.append(@intFromEnum(Type.Plate));
    try buf.append(3); // Plate length
    try buf.appendSlice("ABC"); // Complete plate
    try buf.appendSlice(&[_]u8{ 0, 0 }); // Incomplete timestamp (should be 4 bytes)

    const result = try decode(buf.items, &array, std.testing.allocator);
    try testing.expectEqual(0, result);
    try testing.expectEqual(0, array.len);
    for (&array.buffer) |*msg| msg.deinit();
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

    const bytes_consumed = try decode(buf.items, &array, std.testing.allocator);

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
    for (&array.buffer) |*msg| msg.deinit();
}

// Give me tests for Want Heartbeat
test "decode want heartbeat" {
    var array = try MessageBoundedArray.init(0);
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    const interval: u32 = 12345;
    try buf.append(@intFromEnum(Type.WantHeartbeat));
    var interval_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &interval_bytes, interval, .big);
    try buf.appendSlice(&interval_bytes);
    const bytes_consumed = try decode(buf.items, &array, std.testing.allocator);
    try testing.expectEqual(@as(u16, @intCast(buf.items.len)), bytes_consumed);
    try testing.expectEqual(@as(usize, 1), array.len);
    const msg = array.buffer[0];
    try testing.expectEqual(Type.WantHeartbeat, msg.type);
    try testing.expectEqual(interval, msg.data.want_heartbeat.interval);
    for (&array.buffer) |*msgs| msgs.deinit();
}

// Give me a set of tests with mixed messages
test "decode mixed messages" {
    var array = try MessageBoundedArray.init(0);
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    // Plate message
    const plate = "ABC123";
    const timestamp: u32 = 12345;
    try buf.append(@intFromEnum(Type.Plate));
    try buf.append(plate.len);
    try buf.appendSlice(plate);
    var ts_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &ts_bytes, timestamp, .big);
    try buf.appendSlice(&ts_bytes);
    // Want Heartbeat message
    const interval: u32 = 12345;
    try buf.append(@intFromEnum(Type.WantHeartbeat));
    var interval_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &interval_bytes, interval, .big);
    try buf.appendSlice(&interval_bytes);
    const bytes_consumed = try decode(buf.items, &array, std.testing.allocator);
    try testing.expectEqual(@as(u16, @intCast(buf.items.len)), bytes_consumed);
    try testing.expectEqual(@as(usize, 2), array.len);
    // Check Plate message
    const msg1 = array.buffer[0];
    try testing.expectEqual(Type.Plate, msg1.type);
    try testing.expectEqualStrings(plate, msg1.data.plate.plate);
    try testing.expectEqual(timestamp, msg1.data.plate.timestamp);
    // Check Want Heartbeat message
    const msg2 = array.buffer[1];
    try testing.expectEqual(Type.WantHeartbeat, msg2.type);
    try testing.expectEqual(interval, msg2.data.want_heartbeat.interval);
    for (&array.buffer) |*msg| msg.deinit();
}

test "decode IAmCamera message" {
    var array = try MessageBoundedArray.init(0);
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    const road: u16 = 123;
    const mile: u16 = 456;
    const limit: u16 = 789;
    try buf.append(@intFromEnum(Type.IAmCamera));
    var road_bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &road_bytes, road, .big);
    try buf.appendSlice(&road_bytes);
    var mile_bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &mile_bytes, mile, .big);
    try buf.appendSlice(&mile_bytes);
    var limit_bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &limit_bytes, limit, .big);
    try buf.appendSlice(&limit_bytes);
    const bytes_consumed = try decode(buf.items, &array, std.testing.allocator);
    try testing.expectEqual(@as(u16, @intCast(buf.items.len)), bytes_consumed);
    try testing.expectEqual(@as(usize, 1), array.len);
    const msg = array.buffer[0];
    try testing.expectEqual(Type.IAmCamera, msg.type);
    try testing.expectEqual(road, msg.data.camera.road);
    try testing.expectEqual(mile, msg.data.camera.mile);
    try testing.expectEqual(limit, msg.data.camera.limit);
    for (&array.buffer) |*msgs| msgs.deinit();
}

test "decode IAmDispatcher" {
    var array = try MessageBoundedArray.init(0);
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    const numroads: u8 = 3;
    const roads = [_]u16{ 123, 456, 789 };
    try buf.append(@intFromEnum(Type.IAmDispatcher));
    try buf.append(numroads);
    var i: u8 = 0;
    while (i < numroads) : (i += 1) {
        var road_bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &road_bytes, roads[i], .big);
        try buf.appendSlice(&road_bytes);
    }
    const bytes_consumed = try decode(buf.items, &array, std.testing.allocator);
    try testing.expectEqual(@as(u16, @intCast(buf.items.len)), bytes_consumed);
    try testing.expectEqual(@as(usize, 1), array.len);
    const msg = array.buffer[0];
    try testing.expectEqual(Type.IAmDispatcher, msg.type);
    try testing.expectEqual(numroads, msg.data.dispatcher.numroads);
    i = 0;
    while (i < numroads) : (i += 1) {
        try testing.expectEqual(roads[i], msg.data.dispatcher.roads.items[i]);
    }
    for (&array.buffer) |*msgs| msgs.deinit();
}
