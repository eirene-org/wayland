const std = @import("std");

const wl = @import("wayland");

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

    var client = wl.Client.init(allocator);
    defer client.close();

    const display = try client.connect();

    const registry = try display.request(.get_registry, .{});
    const callback = try display.request(.sync, .{});

    try registry.listen(.global, onRegistryGlobalEvent, null);

    var registration_done = false;
    try callback.listen(.done, onCallbackDoneEvent, &registration_done);

    std.debug.print("name\tversion\tinterface\n", .{});
    while (!registration_done) {
        try client.dispatchMessage();
    }
}
