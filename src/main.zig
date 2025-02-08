const std = @import("std");

fn getSocketPath(allocator: std.mem.Allocator) ![]const u8 {
    const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/run/user/1000";
    const name = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";

    return std.fs.path.join(allocator, &.{ xdg_runtime_dir, name });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const path = try getSocketPath(allocator);
    defer allocator.free(path);

    const stderr = std.io.getStdErr().writer();
    stderr.print("wayland socket path: {s}\n", .{path}) catch {};
}
