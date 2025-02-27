const std = @import("std");

pub const HalfWord = u16;

pub const Word = u32;

pub const UInt = Word;

fn serializeUInt(buffer: []u8, offset: *u16, uint: UInt) void {
    std.mem.copyForwards(u8, buffer[offset.*..], std.mem.asBytes(&uint));
    offset.* += @sizeOf(UInt);
}

fn deserializeUInt(buffer: []const u8, offset: *u16) UInt {
    const uint = std.mem.bytesToValue(UInt, buffer[offset.*..][0..@sizeOf(Word)]);
    offset.* += @sizeOf(UInt);

    return uint;
}

pub const String = [:0]const u8;

fn computeSizeString(string: String) Size {
    return @sizeOf(Word) +
        std.mem.alignForward(u16, @intCast(string.len + 1), @sizeOf(Word));
}

fn serializeString(buffer: []u8, offset: *u16, string: String) void {
    serializeUInt(buffer, offset, @intCast(string.len + 1));

    std.mem.copyForwards(u8, buffer[offset.*..], std.mem.sliceAsBytes(string));
    buffer[offset.*..][string.len] = 0;

    const aligned_len = std.mem.alignForward(u16, @intCast(string.len + 1), @sizeOf(Word));
    offset.* += aligned_len;
}

fn deserializeString(buffer: []const u8, offset: *u16) String {
    const len: u16 = @intCast(deserializeUInt(buffer, offset));
    const string = buffer[offset.*..][0..(len - 1) :0];

    const aligned_size = std.mem.alignForward(u16, len, @sizeOf(Word));
    offset.* += aligned_size;

    return string;
}

pub const Object = enum(Word) {
    display = 1,
    _,
};

fn serializeObject(buffer: []u8, offset: *u16, object: Object) void {
    serializeUInt(buffer, offset, @intFromEnum(object));
}

pub const NewID = struct {
    interface: String,
    version: UInt,
    object: Object,

    const Self = @This();

    fn computeSize(self: *const Self) Size {
        return @intCast(computeSizeString(self.interface) + @sizeOf(UInt) + @sizeOf(Object));
    }

    fn serialize(buffer: []u8, offset: *u16, newID: Self) void {
        serializeString(buffer, offset, newID.interface);
        serializeUInt(buffer, offset, newID.version);
        serializeObject(buffer, offset, newID.object);
    }

    pub fn withInterface(_Interface: type) type {
        return enum(Word) {
            _,

            pub const Type = NewID;
            pub const Interface = _Interface;
        };
    }

    pub fn isEnum(T: type) bool {
        return @typeInfo(T) == .Enum and @hasDecl(T, "Type") and T.Type == NewID;
    }
};

pub const Opcode = HalfWord;
pub const Size = HalfWord;

pub const Header = packed struct {
    id: Object,
    opcode: Opcode,
    size: Size = undefined,

    fn serialize(self: *const Header, buffer: []u8, offset: *u16) void {
        std.mem.copyForwards(u8, buffer[offset.*..], std.mem.asBytes(self));
        offset.* += @sizeOf(Header);
    }
};

pub fn Message(Payload: type) type {
    return struct {
        header: Header,
        payload: Payload,

        const Self = @This();

        pub fn init(header: Header, payload: Payload) Self {
            var self = Self{ .header = header, .payload = payload };
            self.computeSize();
            return self;
        }

        fn computeSize(self: *Self) void {
            var size: u16 = @sizeOf(Header);

            inline for (std.meta.fields(Payload)) |field| {
                switch (field.type) {
                    UInt,
                    Object,
                    => size += @sizeOf(Word),
                    NewID => size += @field(self.payload, field.name).computeSize(),
                    else => switch (@typeInfo(field.type)) {
                        .Enum => size += @sizeOf(Word),
                        else => @compileError("cannot compute the size of the following field: " ++ field.name),
                    },
                }
            }

            self.header.size = size;
        }

        pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            const buffer = try allocator.alloc(u8, self.header.size);
            errdefer allocator.free(buffer);

            var offset: u16 = 0;
            self.header.serialize(buffer, &offset);

            const payload = &self.payload;
            inline for (std.meta.fields(Payload)) |field| {
                switch (field.type) {
                    UInt => serializeUInt(buffer, &offset, @field(payload, field.name)),
                    Object => serializeObject(buffer, &offset, @field(payload, field.name)),
                    NewID => NewID.serialize(buffer, &offset, @field(payload, field.name)),
                    else => switch (@typeInfo(field.type)) {
                        .Enum => serializeUInt(buffer, &offset, @intFromEnum(@field(payload, field.name))),
                        else => @compileError("cannot serialize the following field: " ++ field.name),
                    },
                }
            }

            return buffer;
        }

        pub fn deserialize(buffer: []const u8) Self {
            const header_slice = buffer[0..@sizeOf(Header)];
            const header: Header = @bitCast(header_slice.*);

            var payload: Payload = undefined;
            var offset: u16 = @sizeOf(Header);
            inline for (std.meta.fields(Payload)) |field| {
                switch (field.type) {
                    UInt => @field(payload, field.name) = deserializeUInt(buffer, &offset),
                    String => @field(payload, field.name) = deserializeString(buffer, &offset),
                    else => switch (@typeInfo(field.type)) {
                        else => @compileError("cannot deserialize the following field: " ++ field.name),
                    },
                }
            }

            return .{ .header = header, .payload = payload };
        }
    };
}
