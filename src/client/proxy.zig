const std = @import("std");

const wp = @import("wayland-protocols");

const wl = @import("root.zig");

pub fn Proxy(I: type) type {
    return struct {
        client: *wl.Client,
        object: wp.Object,

        const Self = @This();

        pub const Interface = I;

        const RequestTag = std.meta.Tag(I.Request);
        const EventTag = std.meta.Tag(I.Event);

        fn RequestPayload(comptime opcode: RequestTag) type {
            return std.meta.TagPayload(I.Request, opcode);
        }

        fn EventPayload(comptime opcode: EventTag) type {
            return std.meta.TagPayload(I.Event, opcode);
        }

        fn RequestReturnType(comptime opcode: RequestTag) type {
            const Payload = RequestPayload(opcode);
            if (Payload.ResultInterface) |ResultInterface| return Proxy(ResultInterface);
            return void;
        }

        pub fn request(
            self: *const Self,
            comptime opcode: RequestTag,
            payload: RequestPayload(opcode),
        ) !RequestReturnType(opcode) {
            const Payload = RequestPayload(opcode);
            const QualifiedRequestReturnType = RequestReturnType(opcode);

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

        fn Callback(opcode: EventTag) type {
            const Payload = EventPayload(opcode);

            return struct {
                const T = *const fn (payload: Payload, userdata: ?*anyopaque) void;

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
            comptime opcode: EventTag,
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
