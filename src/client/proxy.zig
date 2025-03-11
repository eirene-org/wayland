const std = @import("std");

const wp = @import("wayland-protocols");

const wl = @import("root.zig");

pub fn Proxy(I: type) type {
    return struct {
        client: *wl.Client,
        object: wp.Object,

        const Self = @This();

        pub const Interface = I;

        pub fn request(
            self: *const Self,
            comptime opcode: std.meta.Tag(I.Request),
            payload: std.meta.TagPayload(I.Request, opcode),
        ) !RequestReturnType(I.Request, opcode) {
            const Payload = std.meta.TagPayload(I.Request, opcode);
            const QualifiedRequestReturnType = RequestReturnType(I.Request, opcode);

            var object: ?wp.Object = null;

            var finalized_payload: Payload = payload;
            if (QualifiedRequestReturnType != void) {
                object = self.client.newObject();
                inline for (@typeInfo(Payload).Struct.fields) |field| {
                    if (Payload.NewIDFieldName) |newIDFieldName| {
                        if (comptime std.mem.eql(u8, field.name, newIDFieldName)) {
                            @field(finalized_payload, field.name) = object.?;
                        }
                    }
                }
            }

            const Message = wp.Message(Payload);
            var message = Message.init(
                .{
                    .id = self.object,
                    .opcode = @intFromEnum(opcode),
                },
                finalized_payload,
            );

            const serializedMessage = try message.serialize(self.client.allocator);
            defer serializedMessage.deinit();

            try self.client.request(serializedMessage);

            if (QualifiedRequestReturnType != void) {
                return QualifiedRequestReturnType{
                    .client = self.client,
                    .object = object.?,
                };
            }
        }

        pub fn listen(
            self: *const Self,
            comptime opcode: std.meta.Tag(I.Event),
            comptime callback: *const fn (payload: std.meta.TagPayload(I.Event, opcode), userdata: ?*anyopaque) void,
            userdata: ?*anyopaque,
        ) !void {
            const Payload = std.meta.TagPayload(I.Event, opcode);

            const eventID = wl.EventID{
                .object = self.object,
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
    if (Payload.ResultInterface) |Interface| return Proxy(Interface);
    return void;
}
