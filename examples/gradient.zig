const std = @import("std");

const wc = @import("wayland-client");
const wp = @import("wayland-protocols");

const Globals = struct {
    wl_registry: wc.Proxy(wp.wl_registry),

    wl_shm: ?wc.Proxy(wp.wl_shm) = null,
    wl_compositor: ?wc.Proxy(wp.wl_compositor) = null,
    xdg_wm_base: ?wc.Proxy(wp.xdg_wm_base) = null,
};

fn onWLRegistryGlobalEvent(payload: wp.wl_registry.Event.Global, userdata: ?*anyopaque) void {
    const globals: *Globals = @alignCast(@ptrCast(userdata));

    inline for (@typeInfo(Globals).Struct.fields[1..]) |field| blk: {
        if (std.mem.eql(u8, field.name, payload.interface)) {
            const Interface = @typeInfo(field.type).Optional.child.Interface;

            const newID = globals.wl_registry.client.newID(Interface);

            globals.wl_registry.request(.bind, .{
                .name = payload.name,
                .id = newID,
            }) catch break :blk;

            @field(globals, field.name) = .{
                .client = globals.wl_registry.client,
                .object = @enumFromInt(@intFromEnum(newID.object)),
            };
        }
    }
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

    var globals = Globals{ .wl_registry = wl_registry };
    try wl_registry.listen(.global, onWLRegistryGlobalEvent, &globals);

    var registration_done = false;
    try wl_callback.listen(.done, onWLCallbackDoneEvent, &registration_done);

    while (!registration_done) {
        try client.dispatchMessage();
    }

    std.debug.print("wl_shm: {}\n", .{globals.wl_shm != null});
    std.debug.print("wl_compositor: {}\n", .{globals.wl_compositor != null});
    std.debug.print("xdg_wm_base: {}\n", .{globals.xdg_wm_base != null});
}
