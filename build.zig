const std = @import("std");

pub fn build(b: *std.Build) void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_args = .{ .target = target, .optimize = optimize };

    // deps
    const args = b.dependency("args", dep_args);
    const ptz = b.dependency("ptz", dep_args);
    const zqlite = b.dependency("zqlite", dep_args);

    // exe
    const exe = b.addExecutable(.{
        .name = "collector",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "args", .module = args.module("args") },
                .{ .name = "ptz", .module = ptz.module("ptz") },
                .{ .name = "zqlite", .module = zqlite.module("zqlite") },
            }
        }),
        // for debug-ability
        .use_lld = true,
        .use_llvm = true,
    });
    b.installArtifact(exe);

    // run step
    const run = b.step("run", "run the tool");

    const cmd = b.addRunArtifact(exe);
    if (b.args) |run_args| {
        cmd.addArgs(run_args);
    }

    run.dependOn(&cmd.step);
}
