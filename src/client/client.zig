const std = @import("std");

const wp = @import("wayland-protocols");

const wl = @import("root.zig");

pub const EventID = struct {
    object: wp.Object,
    opcode: wp.Opcode,
};

pub const EventListenerCallback = *const fn (buffer: []const u8, userdata: ?*anyopaque) void;

pub const EventListener = struct {
    callback: EventListenerCallback,
    optional_userdata: ?*anyopaque,

    const Self = @This();

    fn call(self: *const Self, buffer: []const u8) void {
        self.callback(buffer, self.optional_userdata);
    }
};

const EventListeners = std.AutoHashMap(EventID, EventListener);

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

    pub fn connect(self: *Self) !wl.Proxy(wp.wl_display) {
        const socketPath = try getSocketPath(self.allocator);
        defer self.allocator.free(socketPath);

        std.log.info("wayland socket path: {s}", .{socketPath});

        self.socket = try std.net.connectUnixSocket(socketPath);

        return .{
            .client = self,
            .object = .display,
        };
    }

    pub fn deinit(self: *Self) void {
        self.eventListeners.deinit();
        self.socket.close();
    }

    pub fn newID(self: *Self, Interface: type) wp.NewID {
        const object = self.newObject();

        return .{
            .interface = Interface.NAME,
            .version = Interface.VERSION,
            .object = object,
        };
    }

    pub fn newObject(self: *Self) wp.Object {
        const object: wp.Object = @enumFromInt(self.next_id);
        self.next_id += 1;

        return object;
    }

    pub fn setEventListener(
        self: *Self,
        eventID: EventID,
        eventListener: EventListener,
    ) !void {
        try self.eventListeners.put(eventID, eventListener);
    }

    pub fn unsetEventListener(self: *Self, eventID: EventID) void {
        _ = self.eventListeners.remove(eventID);
    }

    pub fn dispatchMessage(self: *Self) !void {
        const header_size = @sizeOf(wp.Header);

        const header_slice = self.buffer[0..header_size];
        const header_bytes_read = try self.socket.readAll(header_slice);

        if (header_bytes_read < header_size) {
            return error.EOF;
        }

        const header: *const wp.Header = @ptrCast(@alignCast(header_slice));

        const payload_size = header.size - header_size;

        if (payload_size > 0) {
            const payload_slice = self.buffer[header_size..][0..payload_size];
            const payload_bytes_read = try self.socket.readAll(payload_slice);

            if (payload_bytes_read < payload_size) {
                return error.EOF;
            }
        }

        const eventId = EventID{ .object = header.id, .opcode = header.opcode };
        const eventListener = self.eventListeners.get(eventId) orelse return;

        const message_slice = self.buffer[0..header.size];
        eventListener.call(message_slice);
    }

    pub fn request(self: *const Self, serializedMessage: wp.SerializedMessage) !void {
        const iov = [_]std.posix.iovec_const{.{
            .base = serializedMessage.bytes.ptr,
            .len = serializedMessage.bytes.len,
        }};

        var control: ?*const anyopaque = null;
        var controllen: std.posix.socklen_t = 0;

        if (serializedMessage.fd) |fd| {
            const control_message = wp.ControlMessage{ .payload = fd };
            const control_bytes = control_message.serialize();
            control = control_bytes.ptr;
            controllen = @intCast(control_bytes.len);
        }

        const msghdr = std.posix.msghdr_const{
            .name = null,
            .namelen = 0,
            .iov = &iov,
            .iovlen = iov.len,
            .control = control,
            .controllen = controllen,
            .flags = 0,
        };

        _ = try std.posix.sendmsg(self.socket.handle, &msghdr, 0);
    }
};
