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
};

pub const Callback = enum(wl.Word) {
    _,

    pub const Event = union(enum(wl.Opcode)) {
        done: Event.Done,

        pub const Done = struct {
            callback_data: wl.UInt,
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
        };
    };
};
