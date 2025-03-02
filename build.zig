const std = @import("std");

const BuildManagerOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_llvm: ?bool,
    strip: ?bool,
    error_tracing: ?bool,
};

const BuildManagerModules = struct {
    wayland_client: *std.Build.Module,
    wayland_protocols: *std.Build.Module,
};

const BuildManagerSteps = struct {
    check: *std.Build.Step,
    run: *std.Build.Step,
};

const BuildManager = struct {
    b: *std.Build,

    options: BuildManagerOptions,
    modules: BuildManagerModules,
    steps: BuildManagerSteps,

    const Self = @This();

    fn initOptions(b: *std.Build) BuildManagerOptions {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{
            .preferred_optimize_mode = .ReleaseFast,
        });

        const is_debug_mode = optimize == .Debug;

        const use_llvm = b.option(bool, "use_llvm", "Use the LLVM backend") orelse !is_debug_mode;
        const strip = b.option(bool, "strip", "Strip debug symbols") orelse !is_debug_mode;
        const error_tracing = is_debug_mode and use_llvm;

        return .{
            .target = target,
            .optimize = optimize,
            .use_llvm = use_llvm,
            .strip = strip,
            .error_tracing = error_tracing,
        };
    }

    fn initModules(b: *std.Build) BuildManagerModules {
        const wayland_protocols = b.addModule("wayland-protocols", .{
            .root_source_file = b.path("src/protocols/root.zig"),
        });

        const wayland_client = b.addModule("wayland-client", .{
            .root_source_file = b.path("src/client/root.zig"),
            .imports = &.{
                .{ .name = "wayland-protocols", .module = wayland_protocols },
            },
        });

        return .{
            .wayland_protocols = wayland_protocols,
            .wayland_client = wayland_client,
        };
    }

    fn initSteps(b: *std.Build) BuildManagerSteps {
        return .{
            .check = b.step("check", "Check if examples compile"),
            .run = b.step("run", "Run an example (set via `-Dexample`)"),
        };
    }

    fn init(b: *std.Build) Self {
        return .{
            .b = b,
            .options = initOptions(b),
            .modules = initModules(b),
            .steps = initSteps(b),
        };
    }

    fn setupExamples(self: *const Self) !void {
        const selected_example_name_option = self.b.option([]const u8, "example", "The name of the example to run");

        var examples_dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
        defer examples_dir.close();

        var examples_dir_iterator = examples_dir.iterate();

        while (try examples_dir_iterator.next()) |entry| {
            if (entry.kind != .file) continue;

            const example_name = entry.name[0..(entry.name.len - 4)];
            const example_path = self.b.path(self.b.pathJoin(&.{ "examples", entry.name }));

            const example = self.b.addExecutable(.{
                .name = example_name,
                .root_source_file = example_path,
                .target = self.options.target,
                .optimize = self.options.optimize,
                .use_lld = self.options.use_llvm,
                .use_llvm = self.options.use_llvm,
                .strip = self.options.strip,
                .error_tracing = self.options.error_tracing,
            });
            example.root_module.addImport("wayland-client", self.modules.wayland_client);
            example.root_module.addImport("wayland-protocols", self.modules.wayland_protocols);

            self.steps.check.dependOn(&example.step);

            if (selected_example_name_option) |selected_example_name| {
                if (std.mem.eql(u8, example_name, selected_example_name)) {
                    const run_cmd = self.b.addRunArtifact(example);
                    self.steps.run.dependOn(&run_cmd.step);
                    if (self.b.args) |args| {
                        run_cmd.addArgs(args);
                    }
                }
            }
        }
    }
};

pub fn build(b: *std.Build) !void {
    const buildManager = BuildManager.init(b);
    try buildManager.setupExamples();
}
