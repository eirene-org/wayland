const std = @import("std");

const wc = @import("client.zig");
const wire = @import("wire.zig");

pub const Display = enum(wire.Word) {
    _,

    const Self = @This();

    pub const Request = enum(wire.Word) {
        sync,
        get_registry,

        pub const Sync = wire.Message(packed struct {
            callback: wire.Object,
        });

        pub const GetRegistry = wire.Message(packed struct {
            registry: wire.Object,
        });
    };

    pub fn sync(self: *const Self, client: *wc.Client) !Callback {
        const callback = try client.newObject();

        var message = Request.Sync.init(
            .{ .id = @enumFromInt(@intFromEnum(self.*)), .opcode = 0 },
            .{ .callback = callback },
        );

        const messageBytes = try message.serialize(client.allocator);
        defer client.allocator.free(messageBytes);

        try client.request(messageBytes);

        return @enumFromInt(@intFromEnum(callback));
    }

    pub fn getRegistry(self: *const Self, client: *wc.Client) !Registry {
        const registry = try client.newObject();

        var message = Request.GetRegistry.init(
            .{ .id = @enumFromInt(@intFromEnum(self.*)), .opcode = 1 },
            .{ .registry = registry },
        );

        const messageBytes = try message.serialize(client.allocator);
        defer client.allocator.free(messageBytes);

        try client.request(messageBytes);

        return @enumFromInt(@intFromEnum(registry));
    }
};

pub const display: Display = @enumFromInt(@intFromEnum(wire.Object.display));

pub const Callback = enum(wire.Word) {
    _,

    pub const Event = union(enum) {
        done: Event.Done,

        pub const Done = struct {
            callback_data: wire.UInt,

            pub const Interface = Callback;
            pub const Opcode = 0;
        };
    };
};

pub const Registry = enum(wire.Word) {
    _,

    pub const Event = union(enum) {
        global: Event.Global,

        pub const Global = struct {
            name: wire.UInt,
            interface: wire.String,
            version: wire.UInt,

            pub const Interface = Registry;
            pub const Opcode = 0;
        };
    };
};
