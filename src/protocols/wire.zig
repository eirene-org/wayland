const std = @import("std");

pub const HalfWord = u16;

pub const Word = u32;

pub const UInt = packed struct {
    value: Value,

    const Self = @This();
    pub const Value = u32;

    pub inline fn from(value: Value) Self {
        return .{ .value = value };
    }

    pub fn computeSize(_: *const Self) Size {
        return @sizeOf(Word);
    }

    pub fn serialize(self: *const Self, buffer: []u8, offset: *u16) void {
        std.mem.copyForwards(u8, buffer[offset.*..], std.mem.asBytes(&self.value));
        offset.* += @sizeOf(Value);
    }

    pub fn deserialize(buffer: []const u8, offset: *u16) Self {
        const value = std.mem.bytesToValue(Value, buffer[offset.*..][0..@sizeOf(Word)]);
        offset.* += @sizeOf(Value);

        return UInt.from(value);
    }
};

pub const String = struct {
    value: Value,

    const Self = @This();
    pub const Value = [:0]const u8;

    pub inline fn from(value: Value) Self {
        return .{ .value = value };
    }

    pub fn computeSize(self: *const Self) Size {
        return @sizeOf(Word) +
            std.mem.alignForward(u16, @intCast(self.value.len + 1), @sizeOf(Word));
    }

    pub fn serialize(self: *const Self, buffer: []u8, offset: *u16) void {
        UInt.from(@intCast(self.value.len + 1)).serialize(buffer, offset);

        std.mem.copyForwards(u8, buffer[offset.*..], std.mem.sliceAsBytes(self.value));
        buffer[offset.*..][self.value.len] = 0;

        const aligned_len = std.mem.alignForward(u16, @intCast(self.value.len + 1), @sizeOf(Word));
        offset.* += aligned_len;
    }

    pub fn deserialize(buffer: []const u8, offset: *u16) Self {
        const len: u16 = @intCast(UInt.deserialize(buffer, offset).value);
        const value = buffer[offset.*..][0..(len - 1) :0];

        const aligned_size = std.mem.alignForward(u16, len, @sizeOf(Word));
        offset.* += aligned_size;

        return String.from(value);
    }
};

pub const Object = enum(Word) {
    null = 0,
    display = 1,
    _,

    const Self = @This();

    pub fn computeSize(_: *const Self) Size {
        return @sizeOf(Word);
    }

    pub fn serialize(self: *const Self, buffer: []u8, offset: *u16) void {
        UInt.from(@intFromEnum(self.*)).serialize(buffer, offset);
    }

    pub fn deserialize(buffer: []const u8, offset: *u16) Self {
        const uint = UInt.deserialize(buffer, offset);
        return @enumFromInt(uint.value);
    }
};

pub const NewID = struct {
    interface: String,
    version: UInt,
    object: Object,

    const Self = @This();

    pub fn computeSize(self: *const Self) Size {
        return self.interface.computeSize() +
            self.version.computeSize() +
            self.object.computeSize();
    }

    pub fn serialize(self: *const Self, buffer: []u8, offset: *u16) void {
        self.interface.serialize(buffer, offset);
        self.version.serialize(buffer, offset);
        self.object.serialize(buffer, offset);
    }
};

pub const Opcode = HalfWord;
pub const Size = HalfWord;

pub const Header = packed struct {
    id: Object,
    opcode: Opcode,
    size: Size = undefined,

    pub fn serialize(self: *const Header, buffer: []u8, offset: *u16) void {
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

        pub fn computeSize(self: *Self) void {
            var size: u16 = @sizeOf(Header);

            inline for (std.meta.fields(Payload)) |field| {
                switch (field.type) {
                    UInt,
                    String,
                    Object,
                    NewID,
                    => size += @field(self.payload, field.name).computeSize(),
                    else => @compileError("cannot compute the size of the following field: " ++ field.name),
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
                    UInt,
                    String,
                    Object,
                    NewID,
                    => @field(payload, field.name).serialize(buffer, &offset),
                    else => @compileError("cannot serialize the following field: " ++ field.name),
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
                    UInt,
                    String,
                    Object,
                    => @field(payload, field.name) = field.type.deserialize(buffer, &offset),
                    else => @compileError("cannot deserialize the following field: " ++ field.name),
                }
            }

            return .{ .header = header, .payload = payload };
        }
    };
}
