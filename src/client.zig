const std = @import("std");

const wl = @import("wayland.zig");
const wire = @import("wire.zig");

const EventId = struct {
    object: wire.Object,
    opcode: wire.Opcode,
};

const EventListener = *const fn (buffer: []const u8) void;

const EventListeners = std.AutoArrayHashMap(EventId, EventListener);

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

    pub fn connect(self: *Self) !void {
        const socketPath = try getSocketPath(self.allocator);
        defer self.allocator.free(socketPath);

        std.log.info("wayland socket path: {s}", .{socketPath});

        self.socket = try std.net.connectUnixSocket(socketPath);
    }

    pub fn close(self: *Self) void {
        self.eventListeners.deinit();
        self.socket.close();
    }

    pub fn newObject(self: *Self) !wire.Object {
        const id: wire.Object = @enumFromInt(self.next_id);
        self.next_id += 1;

        return id;
    }

    pub fn setEventListener(
        self: *Self,
        Payload: type,
        object: Payload.Interface,
        comptime eventListener: *const fn (payload: Payload) void,
    ) !void {
        const eventId = EventId{
            .object = @enumFromInt(@intFromEnum(object)),
            .opcode = Payload.Opcode,
        };

        const Wrapper = struct {
            fn wrappedEventListener(buffer: []const u8) void {
                const Message = wire.Message(Payload);
                const message = Message.deserialize(buffer);
                eventListener(message.payload);
            }
        };
        try self.eventListeners.put(eventId, Wrapper.wrappedEventListener);
    }

    pub fn dispatchMessage(self: *Self) !void {
        const header_slice = self.buffer[0..@sizeOf(wire.Header)];
        const bytes_read = try self.socket.readAll(header_slice);

        if (bytes_read < @sizeOf(wire.Header)) {
            return error.EOF;
        }

        const header: *const wire.Header = @ptrCast(@alignCast(header_slice));

        const eventId = EventId{ .object = header.id, .opcode = header.opcode };
        const eventListener = self.eventListeners.get(eventId) orelse return;

        const payload_slice = self.buffer[@sizeOf(wire.Header)..header.size];
        _ = try self.socket.readAll(payload_slice);

        const message_slice = self.buffer[0..header.size];
        eventListener(message_slice);
    }

    pub fn request(self: *const Self, bytes: []const u8) !void {
        try self.socket.writeAll(bytes);
    }
};
