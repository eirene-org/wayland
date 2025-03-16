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

        fn Callback(opcode: std.meta.Tag(I.Event)) type {
            const Payload = std.meta.TagPayload(I.Event, opcode);

            return struct {
                const T = *const fn (payload: std.meta.TagPayload(I.Event, opcode), userdata: ?*anyopaque) void;

                fn wrap(comptime callback: T) wl.EventListenerCallback {
                    const Wrapper = struct {
                        fn wrappedCallback(buffer: []const u8, optional_userdata: ?*anyopaque) void {
                            const Message = wp.Message(Payload);
                            const message = Message.deserialize(buffer);

                            callback(message.payload, optional_userdata);
                        }
                    };
                    return Wrapper.wrappedCallback;
                }
            };
        }

        pub fn listen(
            self: *const Self,
            comptime opcode: std.meta.Tag(I.Event),
            comptime optional_callback: ?Callback(opcode).T,
            optional_userdata: ?*anyopaque,
        ) !void {
            const eventID = wl.EventID{
                .object = self.object,
                .opcode = @intFromEnum(opcode),
            };

            const callback = optional_callback orelse {
                self.client.unsetEventListener(eventID);
                return;
            };

            const eventListener = wl.EventListener{
                .callback = Callback(opcode).wrap(callback),
                .optional_userdata = optional_userdata,
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
