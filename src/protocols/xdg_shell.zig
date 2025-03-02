const wp = @import("root.zig");

pub const xdg_wm_base = struct {
    pub const NAME = wp.String.from("xdg_wm_base");
    pub const VERSION = wp.UInt.from(6);

    pub const Request = union(enum(wp.Opcode)) {
        get_xdg_surface: Request.GetXdgSurface = 2,
        pong: Request.Pong,

        pub const GetXdgSurface = struct {
            id: wp.Object = .null,
            surface: wp.Object,

            pub const NewIDFieldName: ?[]const u8 = "id";
            pub const ResultInterface: ?type = xdg_surface;
        };

        pub const Pong = struct {
            serial: wp.UInt,

            pub const NewIDFieldName: ?[]const u8 = null;
            pub const ResultInterface: ?type = null;
        };
    };

    pub const Event = union(enum(wp.Opcode)) {
        ping: Event.Ping,

        pub const Ping = struct {
            serial: wp.UInt,
        };
    };
};

pub const xdg_surface = struct {
    pub const NAME = wp.String.from("xdg_surface");
    pub const VERSION = wp.UInt.from(6);

    pub const Request = union(enum(wp.Opcode)) {
        get_toplevel: Request.GetToplevel = 1,
        ack_configure: Request.AckConfigure = 4,

        pub const GetToplevel = struct {
            id: wp.Object = .null,

            pub const NewIDFieldName: ?[]const u8 = "id";
            pub const ResultInterface: ?type = xdg_toplevel;
        };

        pub const AckConfigure = struct {
            serial: wp.UInt,

            pub const NewIDFieldName: ?[]const u8 = null;
            pub const ResultInterface: ?type = null;
        };
    };

    pub const Event = union(enum(wp.Opcode)) {
        configure: Event.Configure,

        pub const Configure = struct {
            serial: wp.UInt,
        };
    };
};

pub const xdg_toplevel = struct {
    pub const NAME = wp.String.from("xdg_toplevel");
    pub const VERSION = wp.UInt.from(6);

    pub const Request = union(enum(wp.Opcode)) {
        set_title: Request.SetTitle = 2,

        pub const SetTitle = struct {
            title: wp.String,

            pub const NewIDFieldName: ?[]const u8 = null;
            pub const ResultInterface: ?type = null;
        };
    };
};
