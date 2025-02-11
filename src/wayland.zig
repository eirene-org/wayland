const std = @import("std");

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

    fn request(self: *Self, values: []const u32) !void {
        try self.socket.writeAll(std.mem.sliceAsBytes(values));
    }
};

pub const Display = struct {
    pub fn sync(wc: *Client) !void {
        try wc.request(&.{ 1, 0xC << 16 | 0, wc.nextId() });
    }

    pub fn getRegistry(wc: *Client) !u32 {
        const id = wc.nextId();
        try wc.request(&.{ 1, 0xC << 16 | 1, id });
        return id;
    }
};
