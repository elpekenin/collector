const std = @import("std");

pub fn build(b: *std.Build) void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // deps
    const dep_args = .{ .target = target, .optimize = optimize };
    const args = b.dependency("args", dep_args);
    const jetquery = b.dependency("jetquery", dep_args);
    const ptz = b.dependency("ptz", dep_args);

    // exe
    const exe = b.addExecutable(.{
        .name = "collector",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "args", .module = args.module("args") },
                .{ .name = "jetquery", .module = jetquery.module("jetquery") },
                .{ .name = "ptz", .module = ptz.module("ptz") },
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
