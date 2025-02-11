const std = @import("std");

const wl = @import("wayland.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var wc = try wl.Client.connect(allocator);
    defer wc.close();

    _ = try wl.Display.request(&wc, .get_registry);
    _ = try wl.Display.request(&wc, .sync);
}
