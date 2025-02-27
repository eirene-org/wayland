const wp = @import("root.zig");

pub const xdg_wm_base = enum(wp.Word) {
    pub const NAME = "xdg_wm_base";
    pub const VERSION = 6;

    _,
};
