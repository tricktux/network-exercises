const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Utils
    const utils = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Utils tests
    const utils_tests = b.addTest(.{
        .name = "utils-tests",
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(utils_tests);

    // 0 Smoke Test
    const smoke_test = b.addExecutable(.{
        .name = "smoke-test",
        .root_source_file = b.path("src/0-smoke-test/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(smoke_test);

    // 1 Prime Time
    const prime_time = b.addExecutable(.{
        .name = "prime-time",
        .root_source_file = b.path("src/1-prime-time/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    prime_time.root_module.addImport("utils", utils);
    b.installArtifact(prime_time);

    // 1 Prime Time Tests
    const prime_time_tests = b.addTest(.{
        .root_source_file = b.path("src/1-prime-time/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(prime_time_tests);
}
