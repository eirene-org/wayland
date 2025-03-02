const std = @import("std");

const wc = @import("wayland-client");
const wp = @import("wayland-protocols");

const Globals = struct {
    wl_registry: wc.Proxy(wp.wl_registry),

    wl_shm: ?wc.Proxy(wp.wl_shm) = null,
    wl_compositor: ?wc.Proxy(wp.wl_compositor) = null,
    xdg_wm_base: ?wc.Proxy(wp.xdg_wm_base) = null,
};

fn onWlRegistryGlobalEvent(payload: wp.wl_registry.Event.Global, userdata: ?*anyopaque) void {
    const globals: *Globals = @alignCast(@ptrCast(userdata));

    inline for (@typeInfo(Globals).Struct.fields[1..]) |field| blk: {
        if (std.mem.eql(u8, field.name, payload.interface.value)) {
            const Interface = @typeInfo(field.type).Optional.child.Interface;

            const newID = globals.wl_registry.client.newID(Interface);

            globals.wl_registry.request(.bind, .{
                .name = payload.name,
                .id = newID,
            }) catch break :blk;

            @field(globals, field.name) = .{
                .client = globals.wl_registry.client,
                .object = newID.object,
            };
        }
    }
}

fn onWlCallbackDoneEvent(payload: wp.wl_callback.Event.Done, userdata: ?*anyopaque) void {
    _ = payload;

    const registration_done: *bool = @ptrCast(userdata.?);
    registration_done.* = true;
}

fn onXdgWmBasePingEvent(payload: wp.xdg_wm_base.Event.Ping, userdata: ?*anyopaque) void {
    const globals: *Globals = @alignCast(@ptrCast(userdata.?));

    globals.xdg_wm_base.?.request(.pong, .{ .serial = payload.serial }) catch {};
}

const XdgSurfaceConfigureEventUserdata = struct {
    xdg_surface: *const wc.Proxy(wp.xdg_surface),
    configured: bool = false,
};

fn onXdgSurfaceConfigureEvent(payload: wp.xdg_surface.Event.Configure, optional_userdata: ?*anyopaque) void {
    const userdata: *XdgSurfaceConfigureEventUserdata = @alignCast(@ptrCast(optional_userdata.?));

    std.debug.print("the xdg surface is configured\n", .{});

    userdata.xdg_surface.request(.ack_configure, .{ .serial = payload.serial }) catch {};
    userdata.configured = true;
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
    try wl_registry.listen(.global, onWlRegistryGlobalEvent, &globals);

    var registration_done = false;
    try wl_callback.listen(.done, onWlCallbackDoneEvent, &registration_done);

    while (!registration_done) {
        try client.dispatchMessage();
    }

    std.debug.print("wl_shm: {}\n", .{globals.wl_shm != null});
    std.debug.print("wl_compositor: {}\n", .{globals.wl_compositor != null});
    std.debug.print("xdg_wm_base: {}\n", .{globals.xdg_wm_base != null});

    const wl_surface = try globals.wl_compositor.?.request(.create_surface, .{});
    const xdg_surface = try globals.xdg_wm_base.?.request(.get_xdg_surface, .{ .surface = wl_surface.object });
    const xdg_toplevel = try xdg_surface.request(.get_toplevel, .{});

    try wl_surface.request(.commit, .{});

    try globals.xdg_wm_base.?.listen(.ping, onXdgWmBasePingEvent, &globals);

    var xdgSurfaceConfigureEventUserdata = XdgSurfaceConfigureEventUserdata{
        .xdg_surface = &xdg_surface,
    };
    try xdg_surface.listen(.configure, onXdgSurfaceConfigureEvent, &xdgSurfaceConfigureEventUserdata);

    while (!xdgSurfaceConfigureEventUserdata.configured) {
        try client.dispatchMessage();
    }

    _ = xdg_toplevel;
}
