const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    const is_debug_mode = optimize == .Debug;

    const use_llvm = b.option(bool, "use_llvm", "Use the LLVM backend") orelse !is_debug_mode;
    const strip = b.option(bool, "strip", "Strip debug symbols") orelse !is_debug_mode;

    const exe = b.addExecutable(.{
        .name = "eirene",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .use_lld = use_llvm,
        .use_llvm = use_llvm,
        .strip = strip,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
