const std = @import("std");

fn Message(Payload: type) type {
    const size = 8 + @sizeOf(Payload);

    return packed struct {
        id: u32,
        size: u16 = size,
        opcode: u16,
        payload: Payload,

        const Self = @This();

        inline fn asBytes(self: *const Self) *const [size]u8 {
            return @ptrCast(self);
        }
    };
}

pub const Client = struct {
    socket: std.net.Stream,
    id: u32,

    const Self = @This();

    fn getSocketPath(allocator: std.mem.Allocator) ![]const u8 {
        const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/run/user/1000";
        const name = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";

        return std.fs.path.join(allocator, &.{ xdg_runtime_dir, name });
    }

    fn nextId(self: *Self) u32 {
        self.id += 1;
        return self.id;
    }

    pub fn connect(allocator: std.mem.Allocator) !Self {
        const socketPath = try getSocketPath(allocator);
        defer allocator.free(socketPath);

        std.log.info("wayland socket path: {s}", .{socketPath});

        const stream = try std.net.connectUnixSocket(socketPath);

        return .{ .socket = stream, .id = 1 };
    }

    pub fn close(self: *Self) void {
        self.socket.close();
    }

    fn request(self: *Self, bytes: []const u8) !void {
        try self.socket.writeAll(bytes);
    }
};

pub const Display = struct {
    pub fn sync(wc: *Client) !u32 {
        const Payload = packed struct { callback: u32 };
        const callback = wc.nextId();

        const message = Message(Payload){
            .id = 1,
            .opcode = 0,
            .payload = .{ .callback = callback },
        };
        try wc.request(message.asBytes());

        return callback;
    }

    pub fn getRegistry(wc: *Client) !u32 {
        const Payload = packed struct { registry: u32 };
        const registry = wc.nextId();

        const message = Message(Payload){
            .id = 1,
            .opcode = 1,
            .payload = .{ .registry = registry },
        };
        try wc.request(message.asBytes());

        return registry;
    }
};
