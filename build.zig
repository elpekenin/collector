const std = @import("std");

pub fn build(b: *std.Build) void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // deps
    const args = b.dependency("args", .{});
    const jetquery = b.dependency("jetquery", .{});
    const ptz = b.dependency("ptz", .{});

    // exe
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("args", args.module("args"));
    root_module.addImport("jetquery", jetquery.module("jetquery"));
    root_module.addImport("ptz", ptz.module("ptz"));

    const exe = b.addExecutable(.{
        .name = "collector",
        .root_module = root_module,
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
