const std = @import("std");

const wire = @import("wire.zig");

const EventListener = ?*const fn (event: wire.Word, buffer: []const u8) void;

const ObjectInfo = struct {
    eventListener: EventListener,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    socket: std.net.Stream = undefined,

    display: Display = @enumFromInt(@intFromEnum(wire.Object.display)),

    next_id: u32 = 2,
    objects: std.AutoArrayHashMap(wire.Object, ObjectInfo),

    buffer: [std.math.maxInt(u16)]u8 = undefined,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const objects = std.AutoArrayHashMap(wire.Object, ObjectInfo).init(allocator);
        return .{ .allocator = allocator, .objects = objects };
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
        self.objects.deinit();
        self.socket.close();
    }

    fn newObject(self: *Self) !wire.Object {
        const id: wire.Object = @enumFromInt(self.next_id);
        self.next_id += 1;

        const objectInfo = ObjectInfo{ .eventListener = null };
        try self.objects.put(id, objectInfo);

        return id;
    }

    pub fn setEventListener(
        self: *Self,
        Interface: type,
        object: Interface,
        comptime eventListener: *const fn (event: Interface.Event, buffer: []const u8) void,
    ) void {
        if (self.objects.getPtr(@enumFromInt(@intFromEnum(object)))) |objectInfo| {
            const Wrapper = struct {
                fn wrappedEventListener(opcode: u32, buffer: []const u8) void {
                    const event: Interface.Event = @enumFromInt(opcode);
                    eventListener(event, buffer);
                }
            };
            objectInfo.eventListener = Wrapper.wrappedEventListener;
        } else {
            std.log.warn("there is no object with id {d}", .{object});
        }
    }

    pub fn dispatchMessage(self: *Self) !void {
        const header_slice = self.buffer[0..@sizeOf(wire.Header)];
        const bytes_read = try self.socket.readAll(header_slice);

        if (bytes_read < @sizeOf(wire.Header)) {
            return error.EOF;
        }

        const header: *const wire.Header = @ptrCast(@alignCast(header_slice));

        if (self.objects.get(header.id)) |objectInfo| {
            if (objectInfo.eventListener) |eventListener| {
                const payload_slice = self.buffer[@sizeOf(wire.Header)..header.size];
                _ = try self.socket.readAll(payload_slice);

                const message_slice = self.buffer[0..header.size];
                eventListener(header.opcode, message_slice);
            }
        } else {
            std.log.warn("unknown id: {d}", .{header.id});
        }
    }

    fn request(self: *const Self, bytes: []const u8) !void {
        try self.socket.writeAll(bytes);
    }
};

const Display = enum(wire.Word) {
    _,

    const Self = @This();

    pub fn sync(self: *Self) !Callback {
        const client: *Client = @alignCast(@fieldParentPtr("display", self));

        const Payload = packed struct { callback: wire.Object };
        const callback = try client.newObject();

        const message = wire.Message(Payload){
            .header = .{ .id = .display, .size = wire.Message(Payload).size, .opcode = 0 },
            .payload = .{ .callback = callback },
        };
        try client.request(message.asBytes());

        return @enumFromInt(@intFromEnum(callback));
    }

    pub fn getRegistry(self: *Self) !Registry {
        const client: *Client = @alignCast(@fieldParentPtr("display", self));

        const Payload = packed struct { registry: wire.Object };
        const registry = try client.newObject();

        const message = wire.Message(Payload){
            .header = .{ .id = .display, .size = wire.Message(Payload).size, .opcode = 1 },
            .payload = .{ .registry = registry },
        };
        try client.request(message.asBytes());

        return @enumFromInt(@intFromEnum(registry));
    }
};

pub const Callback = enum(wire.Word) {
    _,
};

pub const Registry = enum(wire.Word) {
    _,

    pub const Event = enum(wire.Word) {
        global,

        pub const Global = wire.Message(struct {
            name: wire.UInt,
            interface: wire.String,
            version: wire.UInt,
        });
    };
};
