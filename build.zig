const std = @import("std");

const test_targets = [_]std.zig.CrossTarget{
    .{}, // native
};

const test_paths = [_][]const u8{
    "src/chip8.zig",
    "src/main.zig",
    "src/rom.zig",
    "src/display.zig",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zhip-8",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkSystemLibrary("sdl2");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_exe.step);

    const test_step = b.step("test", "Run unit tests");

    for (test_targets) |test_target| {
        for (test_paths) |test_path| {
            const unit_tests = b.addTest(.{
                .root_source_file = .{ .path = test_path },
                .target = test_target,
            });

            unit_tests.linkSystemLibrary("sdl2");
            unit_tests.linkLibC();
            const run_unit_tests = b.addRunArtifact(unit_tests);
            test_step.dependOn(&run_unit_tests.step);
        }
    }
}
