const std = @import("std");

const wl = @import("wayland.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var wc = try wl.Client.connect(allocator);
    defer wc.close();

    _ = try wl.Display.getRegistry(&wc);
    _ = try wl.Display.sync(&wc);

    var buffer: [100]u8 = undefined;
    const read = try wc.socket.readAll(&buffer);
    std.debug.print("read: {d}\nbuffer: {b}\n", .{ read, buffer });
}
