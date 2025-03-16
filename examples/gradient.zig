const std = @import("std");

const wc = @import("wayland-client");
const wp = @import("wayland-protocols");

const Globals = struct {
    wl_shm: wc.Proxy(wp.wl_shm),
    wl_compositor: wc.Proxy(wp.wl_compositor),
    xdg_wm_base: wc.Proxy(wp.xdg_wm_base),

    const Self = @This();

    const InitUserdata = struct {
        wl_registry: wc.Proxy(wp.wl_registry),
        globals: *Self,

        fn onWlRegistryGlobalEvent(payload: wp.wl_registry.Event.Global, optional_userdata: ?*anyopaque) void {
            const userdata: *@This() = @alignCast(@ptrCast(optional_userdata));

            inline for (@typeInfo(Globals).Struct.fields) |field| blk: {
                if (std.mem.eql(u8, field.name, payload.interface.value)) {
                    const Interface = field.type.Interface;

                    const newID = userdata.wl_registry.client.newID(Interface);

                    userdata.wl_registry.request(.bind, .{
                        .name = payload.name,
                        .id = newID,
                    }) catch break :blk;

                    @field(userdata.globals, field.name) = .{
                        .client = userdata.wl_registry.client,
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
    };

    fn init(client: *wc.Client) !Self {
        var self: Self = undefined;

        const wl_display = try client.connect();

        const wl_registry = try wl_display.request(.get_registry, .{});
        const wl_callback = try wl_display.request(.sync, .{});

        var userdata = InitUserdata{ .wl_registry = wl_registry, .globals = &self };
        try wl_registry.listen(.global, InitUserdata.onWlRegistryGlobalEvent, &userdata);

        var registered = false;
        try wl_callback.listen(.done, InitUserdata.onWlCallbackDoneEvent, &registered);

        while (!registered) {
            try client.dispatchMessage();
        }

        wl_registry.ignore(.global);

        return self;
    }

    const Listeners = struct {
        fn onXdgWmBasePingEvent(payload: wp.xdg_wm_base.Event.Ping, userdata: ?*anyopaque) void {
            const globals: *Globals = @alignCast(@ptrCast(userdata.?));

            globals.xdg_wm_base.request(.pong, .{ .serial = payload.serial }) catch {};
        }
    };

    fn setUpListeners(self: *const Self) !void {
        try self.xdg_wm_base.listen(.ping, Listeners.onXdgWmBasePingEvent, @constCast(self));
    }
};

const Gradient = struct {
    // A vector with the center in the middle of the 256x256x256 cube
    step_colors: [2][3]f32,

    const Self = @This();

    fn init() Self {
        return .{
            .step_colors = .{
                .{ 0xFF / 2, 0xFF / 2, 0xFF / 8 },
                .{ 0xFF / 2, 0xFF / 2, 0xFF - 0xFF / 8 },
            },
        };
    }

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

    fn render(self: *const Self, width: i32, height: i32, data: []u8) void {
        std.debug.assert(data.len == width * height * 4);

        const width_usize: usize = @intCast(width);
        const height_usize: usize = @intCast(height);

        const width_f32: f32 = @floatFromInt(width);
        const height_f32: f32 = @floatFromInt(height);

        var delta: [2]f32 = .{ -width_f32 / 2, -height_f32 / 2 };

        for (0..width_usize) |x| {
            for (0..height_usize) |y| {
                const i = (x + y * width_usize) * 4;
                const pixel = data[i..][0..4];
                const colors = pixel[0..3];

                var p: [2]f32 = .{ @floatFromInt(x), @floatFromInt(y) };

                translate(&p, &delta);
                rotate2d(&p, 45);
                flipSign(&delta);
                translate(&p, &delta);
                flipSign(&delta);

                const k = std.math.clamp(p[0] / width_f32, 0, 1);
                lerp(colors, &self.step_colors, k);

                pixel[3] = 0xFF;
            }
        }
    }
};

const Buffer = struct {
    handle: wc.Proxy(wp.wl_buffer),
    data: []u8,
};

const Buffers = struct {
    array: [2]Buffer = undefined,
    active: u1 = 0,

    const Self = @This();

    fn next(self: *Self) *Buffer {
        const buffer = &self.array[self.active];
        self.active = ~self.active;
        return buffer;
    }
};

const Surface = struct {
    width: i32,
    height: i32,

    xdg_surface: wc.Proxy(wp.xdg_surface),
    wl_surface: wc.Proxy(wp.wl_surface),
    wl_shm_pool: wc.Proxy(wp.wl_shm_pool),

    pool_fd: std.posix.fd_t,
    pool_data: []align(std.mem.page_size) u8,

    buffers: Buffers,
    gradient: Gradient,

    const Self = @This();

    pub const pixel_size = 4;

    pub const InitOptions = struct {
        client: *wc.Client,
        globals: *const Globals,
    };

    fn init(width: i32, height: i32, options: InitOptions) !Self {
        std.debug.assert(width >= 0 and height >= 0);

        var self: Self = undefined;
        self.width = width;
        self.height = height;

        try self.configure(&options);
        try self.prepareBuffers(&options);

        return self;
    }

    fn deinit(self: *Self) void {
        self.wl_shm_pool.request(.destroy, .{}) catch {
            std.log.err("failed to destroy the pool", .{});
        };
        std.posix.munmap(self.pool_data);
        std.posix.close(self.pool_fd);
        self.* = undefined;
    }

    const ConfigureUserdata = struct {
        xdg_surface: *const wc.Proxy(wp.xdg_surface),
        configured: bool = false,

        fn onXdgSurfaceConfigureEvent(payload: wp.xdg_surface.Event.Configure, optional_userdata: ?*anyopaque) void {
            const userdata: *@This() = @alignCast(@ptrCast(optional_userdata.?));

            userdata.xdg_surface.request(.ack_configure, .{ .serial = payload.serial }) catch {};
            userdata.configured = true;
        }
    };

    fn configure(self: *Self, options: *const InitOptions) !void {
        const wl_surface = try options.globals.wl_compositor.request(.create_surface, .{});
        const xdg_surface = try options.globals.xdg_wm_base.request(
            .get_xdg_surface,
            .{ .surface = wl_surface.object },
        );
        _ = try xdg_surface.request(.get_toplevel, .{});

        try wl_surface.request(.commit, .{});

        var userdata = ConfigureUserdata{ .xdg_surface = &xdg_surface };
        try xdg_surface.listen(.configure, ConfigureUserdata.onXdgSurfaceConfigureEvent, &userdata);

        while (!userdata.configured) {
            try options.client.dispatchMessage();
        }

        self.wl_surface = wl_surface;
        self.xdg_surface = xdg_surface;
    }

    fn prepareBuffers(self: *Self, options: *const InitOptions) !void {
        const stride = self.width * pixel_size;
        const framebuffer_size = stride * self.height;
        const framebuffer_size_usize: usize = @intCast(framebuffer_size);
        const pool_size = framebuffer_size * 2;
        const pool_size_usize: usize = @intCast(pool_size);

        const pool_fd = try std.posix.memfd_create("shm_pool", 0);
        try std.posix.ftruncate(pool_fd, pool_size_usize);

        const wl_shm_pool = try options.globals.wl_shm.request(.create_pool, .{
            .fd = wp.Fd.from(pool_fd),
            .size = wp.Int.from(pool_size),
        });

        const pool_data = try std.posix.mmap(
            null,
            pool_size_usize,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            pool_fd,
            0,
        );

        var buffers: Buffers = undefined;
        for (0..buffers.array.len) |i| {
            const offset_usize = framebuffer_size_usize * i;
            const offset_i32: i32 = @intCast(offset_usize);
            const wl_buffer = try wl_shm_pool.request(.create_buffer, .{
                .offset = wp.Int.from(offset_i32),
                .width = wp.Int.from(self.width),
                .height = wp.Int.from(self.height),
                .stride = wp.Int.from(stride),
                .format = wp.wl_shm.Enum.Format.argb8888,
            });
            buffers.array[i] = .{
                .handle = wl_buffer,
                .data = pool_data[offset_usize..][0..framebuffer_size_usize],
            };
        }

        const gradient = Gradient.init();

        self.wl_shm_pool = wl_shm_pool;
        self.pool_fd = pool_fd;
        self.pool_data = pool_data;
        self.buffers = buffers;
        self.gradient = gradient;
    }

    const Listeners = struct {
        fn onXdgSurfaceConfigureEvent(payload: wp.xdg_surface.Event.Configure, optional_userdata: ?*anyopaque) void {
            const xdg_surface: *const wc.Proxy(wp.xdg_surface) = @alignCast(@ptrCast(optional_userdata.?));

            xdg_surface.request(.ack_configure, .{ .serial = payload.serial }) catch {};
        }
    };

    fn setUpListeners(self: *const Self) !void {
        try self.xdg_surface.listen(.configure, Listeners.onXdgSurfaceConfigureEvent, @constCast(&self.xdg_surface));
    }

    fn render(self: *Self) !void {
        const buffer = self.buffers.next();

        self.gradient.render(self.width, self.height, buffer.data);
        self.gradient.next();

        try self.wl_surface.request(.attach, .{
            .buffer = buffer.handle.object,
            .x = wp.Int.from(0),
            .y = wp.Int.from(0),
        });
        try self.wl_surface.request(.damage, .{
            .x = wp.Int.from(0),
            .y = wp.Int.from(0),
            .width = wp.Int.from(self.width),
            .height = wp.Int.from(self.height),
        });
        try self.wl_surface.request(.commit, .{});
    }
};

const SignalHandler = struct {
    var interrupted: bool = false;

    const Self = @This();

    fn interrupt(_: i32) callconv(.C) void {
        interrupted = true;

        const stderr = std.io.getStdErr().writer();
        _ = stderr.write("\rintterrupted\n") catch {};
    }

    fn init() !void {
        const act = std.posix.Sigaction{
            .handler = .{ .handler = interrupt },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        };
        try std.posix.sigaction(std.posix.SIG.INT, &act, null);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var client = wc.Client.init(allocator);
    defer client.deinit();

    const globals = try Globals.init(&client);
    try globals.setUpListeners();

    var surface = try Surface.init(256, 256, .{ .client = &client, .globals = &globals });
    defer surface.deinit();
    try surface.setUpListeners();

    try SignalHandler.init();

    while (!SignalHandler.interrupted) {
        try surface.render();
        try client.dispatchMessage();
        std.time.sleep(10_000_000);
    }
}
