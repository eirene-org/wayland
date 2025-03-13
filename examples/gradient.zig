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

    userdata.xdg_surface.request(.ack_configure, .{ .serial = payload.serial }) catch {};
    userdata.configured = true;
}

fn translate(x: *f32, y: *f32, delta_x: f32, delta_y: f32) void {
    x.* += delta_x;
    y.* += delta_y;
}

fn rotate(x: *f32, y: *f32, angle: f32) void {
    const x_o = x.*;
    const y_o = y.*;

    const radians = std.math.degreesToRadians(angle);

    x.* = x_o * @cos(radians) - y_o * @sin(radians);
    y.* = x_o * @sin(radians) + y_o * @cos(radians);
}

fn lerp(colors: *[3]u8, k: f32) void {
    const step_colors: [2][3]u8 = .{
        .{ 0x00, 0x00, 0xFF },
        .{ 0xFF, 0x00, 0x00 },
    };

    for (0..colors.len) |j| {
        const a: f32 = @floatFromInt(step_colors[0][j]);
        const b: f32 = @floatFromInt(step_colors[1][j]);
        const interpolated_color = a + (b - a) * k;
        colors[j] = @intFromFloat(interpolated_color);
    }
}

fn render(width: comptime_int, height: comptime_int, data: *[width * height * 4]u8) void {
    const width_f32: f32 = @floatFromInt(width);
    const height_f32: f32 = @floatFromInt(height);

    const mx = width_f32 / 2;
    const my = height_f32 / 2;

    for (0..width) |x| {
        for (0..height) |y| {
            const i = (x + y * width) * 4;
            const pixel = data[i..][0..4];
            const colors = pixel[0..3];

            var x_f32: f32 = @floatFromInt(x);
            var y_f32: f32 = @floatFromInt(y);

            translate(&x_f32, &y_f32, -mx, -my);
            rotate(&x_f32, &y_f32, 45);
            translate(&x_f32, &y_f32, mx, my);

            const k = std.math.clamp(x_f32 / width, 0, 1);
            lerp(colors, k);

            pixel[3] = 0xFF;
        }
    }
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

    const width = 256;
    const height = width;
    const pixel_size = 4;
    const stride = width * pixel_size;
    const framebuffer_size = stride * height;
    const pool_size = framebuffer_size * 2;

    const pool_fd = try std.posix.memfd_create("shm_pool", 0);
    try std.posix.ftruncate(pool_fd, pool_size);

    const wl_shm_pool = try globals.wl_shm.?.request(.create_pool, .{
        .fd = wp.Fd.from(pool_fd),
        .size = wp.Int.from(pool_size),
    });

    const index = 0;
    const offset = framebuffer_size * index;
    const wl_buffer = try wl_shm_pool.request(.create_buffer, .{
        .offset = wp.Int.from(offset),
        .width = wp.Int.from(width),
        .height = wp.Int.from(height),
        .stride = wp.Int.from(stride),
        .format = wp.wl_shm.Enum.Format.argb8888,
    });

    const pool_data = try std.posix.mmap(
        null,
        pool_size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        pool_fd,
        0,
    );

    render(width, height, pool_data[offset..][0..framebuffer_size]);

    try wl_surface.request(.attach, .{
        .buffer = wl_buffer.object,
        .x = wp.Int.from(0),
        .y = wp.Int.from(0),
    });
    try wl_surface.request(.damage, .{
        .x = wp.Int.from(0),
        .y = wp.Int.from(0),
        .width = wp.Int.from(0),
        .height = wp.Int.from(0),
    });
    try wl_surface.request(.commit, .{});

    while (true) {
        try client.dispatchMessage();
    }
}
