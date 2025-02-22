const std = @import("std");

const wc = @import("client.zig");
const wl = @import("wayland.zig");

fn onRegistryGlobalEvent(payload: wl.Registry.Event.Global, userdata: ?*anyopaque) void {
    _ = userdata;

    std.debug.print("{}\t{}\t{s}\n", .{ payload.name, payload.version, payload.interface });
}

fn onCallbackDoneEvent(payload: wl.Callback.Event.Done, userdata: ?*anyopaque) void {
    _ = payload;

    const registration_done: *bool = @ptrCast(userdata.?);
    registration_done.* = true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var client = wc.Client.init(allocator);
    defer client.close();

    try client.connect();

    const registry = try wl.display.getRegistry(&client);
    const callback = try wl.display.sync(&client);

    try client.setEventListener(wl.Registry.Event.Global, registry, onRegistryGlobalEvent, null);

    var registration_done = false;
    try client.setEventListener(wl.Callback.Event.Done, callback, onCallbackDoneEvent, &registration_done);

    std.debug.print("name\tversion\tinterface\n", .{});
    while (!registration_done) {
        try client.dispatchMessage();
    }
}
