const wp = @import("root.zig");

pub const xdg_wm_base = enum(wp.Word) {
    pub const NAME = wp.String.from("xdg_wm_base");
    pub const VERSION = wp.UInt.from(6);

    _,
};
