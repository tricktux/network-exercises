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
