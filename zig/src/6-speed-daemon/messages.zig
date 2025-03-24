const std = @import("std");

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
// TODO: Add argument for BoundedArray of Messages
pub fn decode(buf: []const u8, array: *MessageBoundedArray) !u16 {
    if (buf.len < 2) return error.NotEnoughBytes;

    var start: u32 = 0;
    var len: u32 = 0;

    while (true) {
        const mtype = Type(buf[start]);
        switch (mtype) {
            Type.Plate => {
                if (buf.len < 7) return error.NotEnoughBytes;

                // TODO: Add function to convert unix epoch timestamp to date
                std.log.info("(decode): Decoding plate message");
                const platelen = buf[start + 1];
                const platestart = start + 2;
                const plateend = platestart + platelen;
                // TODO: Add buf.len check against plateend
                // TODO: Transfer ownership to the message?
                const plate: []const u8 = buf[platestart..plateend];
                std.log.debug("(decode): plate: {s}", .{plate});

                const timestampstart = platelen + 1;
                const timestampend = platelen + 1 + 4;
                // TODO: Add buf.len check against plateend + 1 + 4
                const timestamp: u32 = std.mem.readVarInt(u32, buf[timestampstart .. timestampend], .big);
                const platem = Plate{
                    .plate = plate,
                    .timestamp = timestamp,
                };
                array.append(Message.initPlate(platem));
            },
            Type.Ticket => {
                if (buf.len < 19) {
                    return ErrorM{ .msg = "Ticket message too short" };
                }
                const ticket = Ticket{
                    .plate = buf[1..6],
                    .road = buf[6] | (buf[7] << 8),
                    .mile1 = buf[8] | (buf[9] << 8),
                    .timestamp1 = buf[10] | (buf[11] << 8) | (buf[12] << 16) | (buf[13] << 24),
                    .mile2 = buf[14] | (buf[15] << 8),
                    .timestamp2 = buf[16] | (buf[17] << 8) | (buf[18] << 16) | (buf[19] << 24),
                    .speed = buf[20] | (buf[21] << 8),
                };
                return Message.initTicket(ticket);
            },
            Type.WantHeartbeat => {
                if (buf.len < 5) {
                    return ErrorM{ .msg = "WantHeartbeat message too short" };
                }
                const interval = buf[1] | (buf[2] << 8) | (buf[3] << 16) | (buf[4] << 24);
                return Message.initWantHeartbeat(interval);
            },
            Type.Hearbeat => {
                return Message.initHeartbeat();
            },
            Type.IAmCamera => {
                if (buf.len < 7) {
                    return ErrorM{ .msg = "IAmCamera message too short" };
                }
                const camera = IAmCamera{
                    .road = buf[1] | (buf[2] << 8),
                    .mile = buf[3] | (buf[4] << 8),
                    .limit = buf[5] | (buf[6] << 8),
                };
                return Message.initCamera(camera);
            },
            Type.IAmDispatcher => {
                if (buf.len < 3) {
                    return ErrorM{ .msg = "IAmDispatcher message too short" };
                }
                const numroads = buf[1] | (buf[2] << 8);
                if (buf.len < 3 + numroads * 2) {
                    return ErrorM{ .msg = "IAmDispatcher message too short" };
                }
                var roads = []u16{numroads};
                for (roads) |road| {
                    road = buf[3 + i * 2] | (buf[4 + i * 2] << 8);
                }
                const dispatcher = IAmDispatcher{
                    .numroads = numroads,
                    .roads = roads,
                };
                return Message.initDispatcher(dispatcher);
            },
            else => return error.InvalidMessageType,
        }
    }
}
