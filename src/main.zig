const std = @import("std");

const wc = @import("client.zig");
const wl = @import("wayland.zig");

fn onRegistryGlobalEvent(payload: wl.Registry.Event.Global, userdata: ?*anyopaque) void {
    _ = userdata;

    std.debug.print("global: {}\n", .{payload});
    std.debug.print("message: name: {d}\n", .{payload.name});
    std.debug.print("message: interface: {s}\n", .{payload.interface});
    std.debug.print("message: version: {d}\n", .{payload.version});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var client = wc.Client.init(allocator);
    defer client.close();

    try client.connect();

    const registry = try wl.display.getRegistry(&client);
    _ = try wl.display.sync(&client);

    try client.setEventListener(wl.Registry.Event.Global, registry, onRegistryGlobalEvent, null);

    try client.dispatchMessage();
}
