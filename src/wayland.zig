const std = @import("std");

const wl = @import("root.zig");

pub const Display = enum(wl.Word) {
    _,

    const Self = @This();

    pub const Request = union(enum(wl.Opcode)) {
        sync: Sync,
        get_registry: GetRegistry,

        pub const Sync = struct {
            callback: wl.NewID.withInterface(Callback) = @enumFromInt(0),
        };

        pub const GetRegistry = struct {
            registry: wl.NewID.withInterface(Registry) = @enumFromInt(0),
        };
    };

    pub fn sync(self: *const Self, client: *wl.Client) !Callback {
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

    pub fn getRegistry(self: *const Self, client: *wl.Client) !Registry {
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

pub const Callback = enum(wl.Word) {
    _,

    pub const Event = union(enum(wl.Opcode)) {
        done: Event.Done,

        pub const Done = struct {
            callback_data: wl.UInt,

            pub const Interface = Callback;
            pub const Opcode = 0;
        };
    };
};

pub const Registry = enum(wl.Word) {
    _,

    pub const Event = union(enum(wl.Opcode)) {
        global: Event.Global,

        pub const Global = struct {
            name: wl.UInt,
            interface: wl.String,
            version: wl.UInt,

            pub const Interface = Registry;
            pub const Opcode = 0;
        };
    };
};
