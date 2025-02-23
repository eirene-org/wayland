const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    const is_debug_mode = optimize == .Debug;

    const use_llvm = b.option(bool, "use_llvm", "Use the LLVM backend") orelse !is_debug_mode;
    const strip = b.option(bool, "strip", "Strip debug symbols") orelse !is_debug_mode;

    const lib = b.addStaticLibrary(.{
        .name = "wayland",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .use_lld = use_llvm,
        .use_llvm = use_llvm,
    });
    b.installArtifact(lib);

    const module = b.addModule("wayland", .{
        .root_source_file = lib.root_module.root_source_file,
    });

    const example_globals = b.addExecutable(.{
        .name = "globals",
        .root_source_file = b.path("examples/globals.zig"),
        .target = target,
        .optimize = optimize,
        .use_lld = use_llvm,
        .use_llvm = use_llvm,
        .strip = strip,
    });
    example_globals.root_module.addImport("wayland", module);

    const check_step = b.step("check", "Check if examples compile");
    check_step.dependOn(&example_globals.step);

    var examples = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator);
    defer examples.deinit();

    try examples.put("globals", example_globals);

    const example_name_option = b.option([]const u8, "example", "The name of the example to run");

    const run_step = b.step("run", "Run an example (set via `-Dexample`)");

    if (example_name_option) |example_name| blk: {
        const example = examples.get(example_name) orelse {
            const stderr = std.io.getStdErr().writer();
            stderr.print("No such example.\n\n", .{}) catch {};

            stderr.print("Available examples:\n", .{}) catch {};
            var available_example_names = examples.keyIterator();
            while (available_example_names.next()) |available_example_name| {
                stderr.print("- {s}\n", .{available_example_name.*}) catch {};
            }

            break :blk;
        };

        const run_cmd = b.addRunArtifact(example);
        run_step.dependOn(&run_cmd.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }
}
