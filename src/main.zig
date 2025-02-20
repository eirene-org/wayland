const std = @import("std");

const wl = @import("wayland.zig");

fn onRegistryMessage(event: wl.Registry.Event, buffer: []const u8) void {
    switch (event) {
        .global => {
            std.debug.print("event: {}\n", .{event});
            const message = wl.Registry.Event.Global.deserialize(buffer);
            std.debug.print("message: name: {d}\n", .{message.payload.name});
            std.debug.print("message: interface: {s}\n", .{message.payload.interface});
            std.debug.print("message: version: {d}\n", .{message.payload.version});
        },
    }
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
