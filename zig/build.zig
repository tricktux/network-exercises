const std = @import("std");

fn set_run_cmd(comptime name: []const u8, b: *std.Build, exe: *std.Build.Step.Compile) void {
    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run-" ++ name, "Run " ++ name);
    run_step.dependOn(&run_cmd.step);
}

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

    set_run_cmd("0-smoke-test", b, smoke_test);

    const utils_tests = b.addTest(.{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_utils_tests = b.addRunArtifact(utils_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const utils_test_step = b.step("utils-tests", "Run utils unit tests");
    // test_step.dependOn(&run_lib_unit_tests.step);
    utils_test_step.dependOn(&run_utils_tests.step);


    // 1 Prime Time
    const prime_time = b.addExecutable(.{
        .name = "prime-time",
        .root_source_file = b.path("src/1-prime-time/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    prime_time.root_module.addImport("utils", utils);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(prime_time);

    set_run_cmd("1-prime-time", b, prime_time);
}
