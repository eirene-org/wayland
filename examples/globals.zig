const std = @import("std");

const wc = @import("wayland-client");
const wp = @import("wayland-protocols");

fn onWLRegistryGlobalEvent(payload: wp.wl_registry.Event.Global, userdata: ?*anyopaque) void {
    _ = userdata;

    std.debug.print("{}\t{}\t{s}\n", .{ payload.name, payload.version, payload.interface });
}

fn onWLCallbackDoneEvent(payload: wp.wl_callback.Event.Done, userdata: ?*anyopaque) void {
    _ = payload;

    const registration_done: *bool = @ptrCast(userdata.?);
    registration_done.* = true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var client = wc.Client.init(allocator);
    defer client.deinit();

    const wl_display = try client.connect();

    const wl_registry = try wl_display.request(.get_registry, .{});
    const wl_callback = try wl_display.request(.sync, .{});

    try wl_registry.listen(.global, onWLRegistryGlobalEvent, null);

    var registration_done = false;
    try wl_callback.listen(.done, onWLCallbackDoneEvent, &registration_done);

    std.debug.print("name\tversion\tinterface\n", .{});
    while (!registration_done) {
        try client.dispatchMessage();
    }
}
