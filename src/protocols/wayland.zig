const wp = @import("root.zig");

pub const wl_display = struct {
    pub const NAME = wp.String.from("wl_display");
    pub const VERSION = wp.UInt.from(1);

    const Self = @This();

    pub const Request = union(enum(wp.Opcode)) {
        sync: Sync,
        get_registry: GetRegistry,

        pub const Sync = struct {
            callback: wp.Object = .null,

            pub const NewIDFieldName: ?[]const u8 = "callback";
            pub const ResultInterface: ?type = wl_callback;
        };

        pub const GetRegistry = struct {
            registry: wp.Object = .null,

            pub const NewIDFieldName: ?[]const u8 = "registry";
            pub const ResultInterface: ?type = wl_registry;
        };
    };

    pub const Event = union(enum(wp.Opcode)) {
        @"error": Event.Error,

        pub const Error = struct {
            object_id: wp.Object,
            code: wp.UInt,
            message: wp.String,
        };
    };
};

pub const wl_registry = struct {
    pub const NAME = wp.String.from("wl_registry");
    pub const VERSION = wp.UInt.from(1);

    pub const Request = union(enum(wp.Opcode)) {
        bind: Request.Bind,

        pub const Bind = struct {
            name: wp.UInt,
            id: wp.NewID,

            pub const NewIDFieldName: ?[]const u8 = null;
            pub const ResultInterface: ?type = null;
        };
    };

    pub const Event = union(enum(wp.Opcode)) {
        global: Event.Global,

        pub const Global = struct {
            name: wp.UInt,
            interface: wp.String,
            version: wp.UInt,
        };
    };
};

pub const wl_callback = struct {
    pub const NAME = wp.String.from("wl_callback");
    pub const VERSION = wp.UInt.from(1);

    pub const Event = union(enum(wp.Opcode)) {
        done: Event.Done,

        pub const Done = struct {
            callback_data: wp.UInt,
        };
    };
};

pub const wl_compositor = struct {
    pub const NAME = wp.String.from("wl_compositor");
    pub const VERSION = wp.UInt.from(6);

    pub const Request = union(enum(wp.Opcode)) {
        create_surface: Request.CreateSurface,

        pub const CreateSurface = struct {
            id: wp.Object = .null,

            pub const NewIDFieldName: ?[]const u8 = "id";
            pub const ResultInterface: ?type = wl_surface;
        };
    };
};

pub const wl_shm_pool = struct {
    pub const NAME = wp.String.from("wl_shm_pool");
    pub const VERSION = wp.UInt.from(2);

    pub const Request = union(enum(wp.Opcode)) {
        create_buffer: Request.CreateBuffer,
        destroy: Request.Destroy,

        pub const CreateBuffer = struct {
            id: wp.Object = .null,
            offset: wp.Int,
            width: wp.Int,
            height: wp.Int,
            stride: wp.Int,
            format: wp.UInt,

            pub const NewIDFieldName: ?[]const u8 = "id";
            pub const ResultInterface: ?type = wl_buffer;
        };

        pub const Destroy = struct {
            pub const NewIDFieldName: ?[]const u8 = null;
            pub const ResultInterface: ?type = null;
        };
    };
};

pub const wl_shm = struct {
    pub const NAME = wp.String.from("wl_shm");
    pub const VERSION = wp.UInt.from(2);

    pub const Request = union(enum(wp.Opcode)) {
        create_pool: Request.CreatePool,

        pub const CreatePool = struct {
            id: wp.Object = .null,
            fd: wp.Fd,
            size: wp.Int,

            pub const NewIDFieldName: ?[]const u8 = "id";
            pub const ResultInterface: ?type = wl_shm_pool;
        };
    };

    pub const Enum = struct {
        pub const Format = struct {
            pub const argb8888 = wp.UInt.from(0);
            pub const xrgb8888 = wp.UInt.from(1);
        };
    };
};

pub const wl_buffer = struct {
    pub const NAME = wp.String.from("wl_buffer");
    pub const VERSION = wp.UInt.from(1);
};

pub const wl_surface = struct {
    pub const NAME = wp.String.from("wl_surface");
    pub const VERSION = wp.UInt.from(6);

    pub const Request = union(enum(wp.Opcode)) {
        attach: Request.Attach = 1,
        damage: Request.Damage,
        frame: Request.Frame,
        commit: Request.Commit = 6,

        pub const Attach = struct {
            buffer: wp.Object,
            x: wp.Int,
            y: wp.Int,

            pub const NewIDFieldName: ?[]const u8 = null;
            pub const ResultInterface: ?type = null;
        };

        pub const Damage = struct {
            x: wp.Int,
            y: wp.Int,
            width: wp.Int,
            height: wp.Int,

            pub const NewIDFieldName: ?[]const u8 = null;
            pub const ResultInterface: ?type = null;
        };

        pub const Frame = struct {
            callback: wp.Object = .null,

            pub const NewIDFieldName: ?[]const u8 = "callback";
            pub const ResultInterface: ?type = wl_callback;
        };

        pub const Commit = struct {
            pub const NewIDFieldName: ?[]const u8 = null;
            pub const ResultInterface: ?type = null;
        };
    };
};
