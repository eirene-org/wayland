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

const Gradient = struct {
    // A vector with the center in the middle of the 256x256x256 cube
    step_colors: [2][3]f32 = .{
        .{ 0xFF / 2, 0xFF / 2, 0xFF / 8 },
        .{ 0xFF / 2, 0xFF / 2, 0xFF - 0xFF / 8 },
    },

    const Self = @This();

    fn flipSign(slice: []f32) void {
        for (slice) |*e| {
            e.* = -e.*;
        }
    }

    fn translate(point: []f32, delta: []const f32) void {
        std.debug.assert(point.len == delta.len);
        for (0..point.len) |i| {
            point[i] += delta[i];
        }
    }

    fn rotate2d(point: *[2]f32, theta_deg: f32) void {
        const p: [2]f32 = point.*;

        const theta_rad = std.math.degreesToRadians(theta_deg);

        point[0] = p[0] * @cos(theta_rad) - p[1] * @sin(theta_rad);
        point[1] = p[0] * @sin(theta_rad) + p[1] * @cos(theta_rad);
    }

    fn rotate3d(point: *[3]f32, alpha_deg: f32, beta_deg: f32, gamma_deg: f32) void {
        const p: [3]f32 = point.*;

        const alpha_rad = std.math.degreesToRadians(alpha_deg);
        const beta_rad = std.math.degreesToRadians(beta_deg);
        const gamma_rad = std.math.degreesToRadians(gamma_deg);

        point[0] =
            p[0] * @cos(beta_rad) * @cos(gamma_rad) +
            p[1] * (-@sin(gamma_rad) * @cos(beta_rad)) +
            p[2] * @sin(beta_rad);

        point[1] =
            p[0] * (@sin(alpha_rad) * @sin(beta_rad) * @cos(gamma_rad) + @sin(gamma_rad) * @cos(alpha_rad)) +
            p[1] * (-@sin(alpha_rad) * @sin(beta_rad) * @sin(gamma_rad) + @cos(alpha_rad) * @cos(gamma_rad)) +
            p[2] * (-@sin(alpha_rad) * @cos(beta_rad));

        point[2] =
            p[0] * (@sin(alpha_rad) * @sin(gamma_rad) - @sin(beta_rad) * @cos(alpha_rad) * @cos(gamma_rad)) +
            p[1] * (@sin(alpha_rad) * @cos(gamma_rad) + @sin(beta_rad) * @sin(gamma_rad) * @cos(alpha_rad)) +
            p[2] * @cos(alpha_rad) * @cos(beta_rad);
    }

    fn lerp(colors: *[3]u8, step_colors: *const [2][3]f32, k: f32) void {
        for (0..colors.len) |j| {
            const a: f32 = step_colors[0][j];
            const b: f32 = step_colors[1][j];
            const interpolated_color = a + (b - a) * k;
            colors[j] = @intFromFloat(interpolated_color);
        }
    }

    fn next(self: *Self) void {
        var delta: [3]f32 = .{-0xFF / 2} ** 3;

        for (&self.step_colors) |*step_color| {
            translate(step_color, &delta);
            rotate3d(step_color, 1, 1, 1);
            flipSign(&delta);
            translate(step_color, &delta);
            flipSign(&delta);
        }
    }

    fn render(self: *const Self, width: comptime_int, height: comptime_int, data: *[width * height * 4]u8) void {
        const width_f32: f32 = @floatFromInt(width);
        const height_f32: f32 = @floatFromInt(height);

        var delta: [2]f32 = .{ -width_f32 / 2, -height_f32 / 2 };

        for (0..width) |x| {
            for (0..height) |y| {
                const i = (x + y * width) * 4;
                const pixel = data[i..][0..4];
                const colors = pixel[0..3];

                var p: [2]f32 = .{ @floatFromInt(x), @floatFromInt(y) };

                translate(&p, &delta);
                rotate2d(&p, 45);
                flipSign(&delta);
                translate(&p, &delta);
                flipSign(&delta);

                const k = std.math.clamp(p[0] / width, 0, 1);
                lerp(colors, &self.step_colors, k);

                pixel[3] = 0xFF;
            }
        }
    }
};

const Buffers = [2]wc.Proxy(wp.wl_buffer);

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

    const pool_data = try std.posix.mmap(
        null,
        pool_size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        pool_fd,
        0,
    );

    var buffers: Buffers = undefined;
    for (0..buffers.len) |i| {
        const offset: i32 = @intCast(framebuffer_size * i);
        buffers[i] = try wl_shm_pool.request(.create_buffer, .{
            .offset = wp.Int.from(offset),
            .width = wp.Int.from(width),
            .height = wp.Int.from(height),
            .stride = wp.Int.from(stride),
            .format = wp.wl_shm.Enum.Format.argb8888,
        });
    }

    var gradient = Gradient{};

    while (true) {
        for (0..buffers.len) |i| {
            const offset = framebuffer_size * i;
            gradient.render(width, height, pool_data[offset..][0..framebuffer_size]);
            gradient.next();

            const wl_buffer = buffers[i];

            try wl_surface.request(.attach, .{
                .buffer = wl_buffer.object,
                .x = wp.Int.from(0),
                .y = wp.Int.from(0),
            });
            try wl_surface.request(.damage, .{
                .x = wp.Int.from(0),
                .y = wp.Int.from(0),
                .width = wp.Int.from(width),
                .height = wp.Int.from(height),
            });
            try wl_surface.request(.commit, .{});

            std.time.sleep(10000000);
        }

        try client.dispatchMessage();
    }
}
