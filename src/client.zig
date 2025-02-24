const std = @import("std");

const wl = @import("root.zig");

pub const EventID = struct {
    object: wl.Object,
    opcode: wl.Opcode,
};

pub const EventListener = struct {
    callback: *const fn (buffer: []const u8, userdata: ?*anyopaque) void,
    userdata: ?*anyopaque,

    const Self = @This();

    fn call(self: *const Self, buffer: []const u8) void {
        self.callback(buffer, self.userdata);
    }
};

const EventListeners = std.AutoArrayHashMap(EventID, EventListener);

pub const Client = struct {
    allocator: std.mem.Allocator,
    socket: std.net.Stream = undefined,

    next_id: u32 = 2,
    eventListeners: EventListeners,

    buffer: [std.math.maxInt(u16)]u8 = undefined,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const eventListeners = EventListeners.init(allocator);
        return .{ .allocator = allocator, .eventListeners = eventListeners };
    }

    fn getSocketPath(allocator: std.mem.Allocator) ![]const u8 {
        const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/run/user/1000";
        const name = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";

        return std.fs.path.join(allocator, &.{ xdg_runtime_dir, name });
    }

    pub fn connect(self: *Self) !wl.Proxy(wl.Display) {
        const socketPath = try getSocketPath(self.allocator);
        defer self.allocator.free(socketPath);

        std.log.info("wayland socket path: {s}", .{socketPath});

        self.socket = try std.net.connectUnixSocket(socketPath);

        return .{
            .object = @enumFromInt(@intFromEnum(wl.Object.display)),
            .client = self,
        };
    }

    pub fn deinit(self: *Self) void {
        self.eventListeners.deinit();
        self.socket.close();
    }

    pub fn newObject(self: *Self) !wl.Object {
        const id: wl.Object = @enumFromInt(self.next_id);
        self.next_id += 1;

        return id;
    }

    pub fn setEventListener(
        self: *Self,
        eventID: EventID,
        eventListener: EventListener,
    ) !void {
        try self.eventListeners.put(eventID, eventListener);
    }

    pub fn dispatchMessage(self: *Self) !void {
        const header_slice = self.buffer[0..@sizeOf(wl.Header)];
        const bytes_read = try self.socket.readAll(header_slice);

        if (bytes_read < @sizeOf(wl.Header)) {
            return error.EOF;
        }

        const header: *const wl.Header = @ptrCast(@alignCast(header_slice));

        const eventId = EventID{ .object = header.id, .opcode = header.opcode };
        const eventListener = self.eventListeners.get(eventId) orelse return;

        const payload_slice = self.buffer[@sizeOf(wl.Header)..header.size];
        _ = try self.socket.readAll(payload_slice);

        const message_slice = self.buffer[0..header.size];
        eventListener.call(message_slice);
    }

    pub fn request(self: *const Self, bytes: []const u8) !void {
        try self.socket.writeAll(bytes);
    }
};
