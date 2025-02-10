const std = @import("std");

const Display = struct {
    const OpCode = enum(u32) { sync, get_registry };

    fn request(wc: *WaylandClient, opCode: OpCode) !u32 {
        const DISPLAY_ID = 1;

        try wc.socket.writeAll(std.mem.sliceAsBytes(&[_]u32{
            DISPLAY_ID,
            0xC << 16 | @intFromEnum(opCode),
            wc.id,
        }));

        wc.id += 1;
        return wc.id;
    }
};

const WaylandClient = struct {
    socket: std.net.Stream,
    id: u32,

    const Self = @This();

    fn getSocketPath(allocator: std.mem.Allocator) ![]const u8 {
        const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/run/user/1000";
        const name = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";

        return std.fs.path.join(allocator, &.{ xdg_runtime_dir, name });
    }

    fn connect(allocator: std.mem.Allocator) !Self {
        const socketPath = try getSocketPath(allocator);
        defer allocator.free(socketPath);

        std.log.info("wayland socket path: {s}", .{socketPath});

        const stream = try std.net.connectUnixSocket(socketPath);

        return .{ .socket = stream, .id = 1 };
    }

    fn close(self: *Self) void {
        self.socket.close();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var wc = try WaylandClient.connect(allocator);
    defer wc.close();

    _ = try Display.request(&wc, .get_registry);
    _ = try Display.request(&wc, .sync);
}
