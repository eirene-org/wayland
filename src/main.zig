const std = @import("std");

const wl = @import("wayland.zig");

fn onRegistryMessage() void {
    std.debug.print("got a message from the registry object\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var wc = wl.Client.init(allocator);
    defer wc.close();

    try wc.connect();

    const registry = try wc.display.getRegistry();
    _ = try wc.display.sync();

    wc.setEventListener(wl.Registry, registry, onRegistryMessage);

    try wc.dispatchMessage();
}
