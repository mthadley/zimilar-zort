const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable(.{
        .name = "zimilar-zort",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    setup_tests(b);
}

fn setup_tests(b: *std.Build) void {
    const test_step = b.step("test", "Run unit tests");

    const main_test = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
    });
    const run_main_test = b.addRunArtifact(main_test);

    test_step.dependOn(&run_main_test.step);
}
