const std = @import("std");

pub const Header = packed struct {
    id: u32,
    opcode: u16,
    size: u16,
};

fn Message(Payload: type) type {
    return packed struct {
        header: Header,
        payload: Payload,

        const Self = @This();

        const size = @sizeOf(Header) + @sizeOf(Payload);

        inline fn asBytes(self: *const Self) *const [size]u8 {
            return @ptrCast(self);
        }

        pub fn read(client: *Client) !Self {
            var self: Self = undefined;
            _ = try client.socket.readAll(std.mem.asBytes(&self));
            return self;
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

    const ID = enum(u32) {
        _,
    };

    pub fn sync(self: *Self) !Callback.ID {
        const client: *Client = @alignCast(@fieldParentPtr("display", self));

        const Payload = packed struct { callback: u32 };
        const callback = client.nextId();

        const message = Message(Payload){
            .header = .{ .id = 1, .size = Message(Payload).size, .opcode = 0 },
            .payload = .{ .callback = callback },
        };
        try client.request(message.asBytes());

        return @enumFromInt(callback);
    }

    pub fn getRegistry(self: *Self) !Registry.ID {
        const client: *Client = @alignCast(@fieldParentPtr("display", self));

        const Payload = packed struct { registry: u32 };
        const registry = client.nextId();

        const message = Message(Payload){
            .header = .{ .id = 1, .size = Message(Payload).size, .opcode = 1 },
            .payload = .{ .registry = registry },
        };
        try client.request(message.asBytes());

        return @enumFromInt(registry);
    }
};

const Callback = struct {
    const ID = enum(u32) {
        _,
    };
};

const Registry = struct {
    const ID = enum(u32) {
        _,
    };
};
