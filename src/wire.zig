const std = @import("std");

pub const Word = u32;

pub const UInt = Word;

fn deserializeUInt(buffer: []const u8, offset: *u16) UInt {
    const uint = std.mem.bytesToValue(UInt, buffer[offset.*..][0..@sizeOf(Word)]);
    offset.* += @sizeOf(UInt);

    return uint;
}

pub const String = [:0]const u8;

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

pub const Header = packed struct {
    id: Object,
    opcode: u16,
    size: u16,
};

pub fn Message(Payload: type) type {
    return struct {
        header: Header,
        payload: Payload,

        const Self = @This();

        pub const size = @sizeOf(Header) + @sizeOf(Payload);

        pub inline fn asBytes(self: *const Self) *const [size]u8 {
            return @ptrCast(self);
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
                    else => {},
                }
            }

            return .{ .header = header, .payload = payload };
        }
    };
}
