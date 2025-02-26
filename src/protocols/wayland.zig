const wp = @import("root.zig");

pub const wl_display = enum(wp.Word) {
    _,

    const Self = @This();

    pub const Request = union(enum(wp.Opcode)) {
        sync: Sync,
        get_registry: GetRegistry,

        pub const Sync = struct {
            callback: wp.NewID.withInterface(wl_callback) = @enumFromInt(0),
        };

        pub const GetRegistry = struct {
            registry: wp.NewID.withInterface(wl_registry) = @enumFromInt(0),
        };
    };
};

pub const wl_callback = enum(wp.Word) {
    _,

    pub const Event = union(enum(wp.Opcode)) {
        done: Event.Done,

        pub const Done = struct {
            callback_data: wp.UInt,
        };
    };
};

pub const wl_registry = enum(wp.Word) {
    _,

    pub const Event = union(enum(wp.Opcode)) {
        global: Event.Global,

        pub const Global = struct {
            name: wp.UInt,
            interface: wp.String,
            version: wp.UInt,
        };
    };
};
