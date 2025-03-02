const wp = @import("root.zig");

pub const xdg_wm_base = struct {
    pub const NAME = wp.String.from("xdg_wm_base");
    pub const VERSION = wp.UInt.from(6);

};
