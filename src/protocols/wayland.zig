const wp = @import("root.zig");

pub const wl_display = enum(wp.Word) {
    _,

    pub const NAME = "wl_display";
    pub const VERSION = 1;

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

pub const wl_registry = enum(wp.Word) {
    _,

    pub const NAME = "wl_registry";
    pub const VERSION = 1;

    pub const Event = union(enum(wp.Opcode)) {
        global: Event.Global,

        pub const Global = struct {
            name: wp.UInt,
            interface: wp.String,
            version: wp.UInt,
        };
    };
};

pub const wl_callback = enum(wp.Word) {
    _,

    pub const NAME = "wl_callback";
    pub const VERSION = 1;

    pub const Event = union(enum(wp.Opcode)) {
        done: Event.Done,

        pub const Done = struct {
            callback_data: wp.UInt,
        };
    };
};

pub const wl_compositor = enum(wp.Word) {
    _,

    pub const NAME = "wl_compositor";
    pub const VERSION = 6;
};

pub const wl_shm = enum(wp.Word) {
    _,

    pub const NAME = "wl_shm";
    pub const VERSION = 2;
};
