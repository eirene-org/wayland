const std = @import("std");

const wp = @import("wayland-protocols");

const wl = @import("root.zig");

pub fn Proxy(Interface: type) type {
    return struct {
        object: Interface,
        client: *wl.Client,

        const Self = @This();

        pub fn request(
            self: *const Self,
            comptime opcode: std.meta.Tag(Interface.Request),
            _payload: std.meta.TagPayload(Interface.Request, opcode),
        ) !RequestReturnType(Interface.Request, opcode) {
            const Payload = std.meta.TagPayload(Interface.Request, opcode);

            const new_object = try self.client.newObject();

            var payload: Payload = _payload;
            inline for (@typeInfo(Payload).Struct.fields) |field| {
                if (comptime wp.NewID.isEnum(field.type)) {
                    @field(payload, field.name) = @enumFromInt(@intFromEnum(new_object));
                }
            }

            const Message = wp.Message(Payload);
            var message = Message.init(
                .{
                    .id = @enumFromInt(@intFromEnum(self.object)),
                    .opcode = @intFromEnum(opcode),
                },
                payload,
            );

            const messageBytes = try message.serialize(self.client.allocator);
            defer self.client.allocator.free(messageBytes);

            try self.client.request(messageBytes);

            const QualifiedRequestReturnType = RequestReturnType(Interface.Request, opcode);
            if (QualifiedRequestReturnType != void) {
                return QualifiedRequestReturnType{
                    .object = @enumFromInt(@intFromEnum(new_object)),
                    .client = self.client,
                };
            }
        }

        pub fn listen(
            self: *const Self,
            comptime opcode: std.meta.Tag(Interface.Event),
            comptime callback: *const fn (payload: std.meta.TagPayload(Interface.Event, opcode), userdata: ?*anyopaque) void,
            userdata: ?*anyopaque,
        ) !void {
            const Payload = std.meta.TagPayload(Interface.Event, opcode);

            const eventID = wl.EventID{
                .object = @enumFromInt(@intFromEnum(self.object)),
                .opcode = @intFromEnum(opcode),
            };

            const Wrapper = struct {
                fn wrappedCallback(buffer: []const u8, _userdata: ?*anyopaque) void {
                    const Message = wp.Message(Payload);
                    const message = Message.deserialize(buffer);

                    callback(message.payload, _userdata);
                }
            };

            const eventListener = wl.EventListener{
                .callback = Wrapper.wrappedCallback,
                .userdata = userdata,
            };
            try self.client.setEventListener(eventID, eventListener);
        }
    };
}

fn RequestReturnType(Request: type, comptime opcode: std.meta.Tag(Request)) type {
    const Payload = std.meta.TagPayload(Request, opcode);
    inline for (@typeInfo(Payload).Struct.fields) |field| {
        if (wp.NewID.isEnum(field.type)) {
            return Proxy(field.type.Interface);
        }
    }
    return void;
}
