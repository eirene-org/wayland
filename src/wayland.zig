const std = @import("std");

fn Message(Payload: type) type {
    const size = 8 + @sizeOf(Payload);

    const Header = packed struct {
        id: u32,
        size: u16 = size,
        opcode: u16,
    };

    return packed struct {
        header: Header,
        payload: Payload,

        const Self = @This();

        inline fn asBytes(self: *const Self) *const [size]u8 {
            return @ptrCast(self);
        }
    };
}

pub const Client = struct {
    socket: std.net.Stream,
    id: u32 = 1,

    display: Display = .{},

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

        return .{ .socket = stream };
    }

    pub fn close(self: *const Self) void {
        self.socket.close();
    }

    fn request(self: *const Self, bytes: []const u8) !void {
        try self.socket.writeAll(bytes);
    }
};

const Display = struct {
    const Self = @This();

    pub fn sync(self: *Self) !u32 {
        const client: *Client = @alignCast(@fieldParentPtr("display", self));

        const Payload = packed struct { callback: u32 };
        const callback = client.nextId();

        const message = Message(Payload){
            .header = .{ .id = 1, .opcode = 0 },
            .payload = .{ .callback = callback },
        };
        try client.request(message.asBytes());

        return callback;
    }

    pub fn getRegistry(self: *Self) !u32 {
        const client: *Client = @alignCast(@fieldParentPtr("display", self));

        const Payload = packed struct { registry: u32 };
        const registry = client.nextId();

        const message = Message(Payload){
            .header = .{ .id = 1, .opcode = 1 },
            .payload = .{ .registry = registry },
        };
        try client.request(message.asBytes());

        return registry;
    }
};
