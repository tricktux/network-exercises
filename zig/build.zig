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

    // Set
    const ziglangSet = b.dependency("ziglangSet", .{});

    // Utils
    const utils = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Utils tests
    const utils_tests = b.addTest(.{
        .name = "utils-tests",
        .root_module = utils,
    });

    b.installArtifact(utils_tests);

    // 0 Smoke Test
    // const smoke_test = b.addModule("smoke-test", .{
    //     .root_source_file = b.path("src/0-smoke-test/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // 1 Prime Time
    // const prime_time = b.addExecutable(.{
    //     .name = "prime-time",
    //     .root_module = b.createModule(.{
    //         // b.createModule defines a new module just like b.addModule but,
    //         // unlike b.addModule, it does not expose the module to consumers of
    //         // this package, which is why in this case we don't have to give it a name.
    //         .root_source_file = b.path("src/1-prime-time/main.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         // List of modules available for import in source files part of the
    //         // root module.
    //     }),
    // });
    // prime_time.root_module.addImport("utils", utils);
    // b.installArtifact(prime_time);
    //
    // // 1 Prime Time Tests
    // const prime_time_tests = b.addTest(.{
    //     .name = "prime-time-tests",
    //     .root_module = b.createModule(.{
    //         // b.createModule defines a new module just like b.addModule but,
    //         // unlike b.addModule, it does not expose the module to consumers of
    //         // this package, which is why in this case we don't have to give it a name.
    //         .root_source_file = b.path("src/1-prime-time/main.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         // List of modules available for import in source files part of the
    //         // root module.
    //     }),
    // });
    // b.installArtifact(prime_time_tests);
    //
    // // 2 Means to an end
    // const means2an_end = b.addExecutable(.{
    //     .name = "means-to-an-end",
    //     .root_module = b.createModule(.{
    //         // b.createModule defines a new module just like b.addModule but,
    //         // unlike b.addModule, it does not expose the module to consumers of
    //         // this package, which is why in this case we don't have to give it a name.
    //         .root_source_file = b.path("src/2-means-to-an-end/main.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         // List of modules available for import in source files part of the
    //         // root module.
    //     }),
    // });
    // b.installArtifact(means2an_end);
    //
    // // 2 Means to an end Tests
    // const means2an_end_tests = b.addTest(.{
    //     .name = "means-to-an-end-tests",
    //     .root_module = b.createModule(.{
    //         // b.createModule defines a new module just like b.addModule but,
    //         // unlike b.addModule, it does not expose the module to consumers of
    //         // this package, which is why in this case we don't have to give it a name.
    //         .root_source_file = b.path("src/2-means-to-an-end/main.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         // List of modules available for import in source files part of the
    //         // root module.
    //     }),
    // });
    // b.installArtifact(means2an_end_tests);
    //
    // // 3 Budget Chat
    // const budget_chat = b.addExecutable(.{
    //     .name = "budget-chat",
    //     .root_module = b.createModule(.{
    //         // b.createModule defines a new module just like b.addModule but,
    //         // unlike b.addModule, it does not expose the module to consumers of
    //         // this package, which is why in this case we don't have to give it a name.
    //         .root_source_file = b.path("src/3-budget-chat/main.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         // List of modules available for import in source files part of the
    //         // root module.
    //     }),
    // });
    // b.installArtifact(budget_chat);
    //
    // // 3 Budget Chat
    // const budget_chat_tests = b.addTest(.{
    //     .name = "budget-chat-tests",
    //     .root_module = b.createModule(.{
    //         // b.createModule defines a new module just like b.addModule but,
    //         // unlike b.addModule, it does not expose the module to consumers of
    //         // this package, which is why in this case we don't have to give it a name.
    //         .root_source_file = b.path("src/3-budget-chat/main.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         // List of modules available for import in source files part of the
    //         // root module.
    //     }),
    // });
    // b.installArtifact(budget_chat_tests);
    //
    // // 4 Unusual Database Program
    // const unusual_database = b.addExecutable(.{
    //     .name = "unusual-database",
    //     .root_module = b.createModule(.{
    //         // b.createModule defines a new module just like b.addModule but,
    //         // unlike b.addModule, it does not expose the module to consumers of
    //         // this package, which is why in this case we don't have to give it a name.
    //         .root_source_file = b.path("src/4-unusual-database/main.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         // List of modules available for import in source files part of the
    //         // root module.
    //     }),
    // });
    // b.installArtifact(unusual_database);
    //
    // // 4 Unusual Database Program
    // const unusual_database_tests = b.addTest(.{
    //     .name = "unusual-database-tests",
    //     .root_module = b.createModule(.{
    //         // b.createModule defines a new module just like b.addModule but,
    //         // unlike b.addModule, it does not expose the module to consumers of
    //         // this package, which is why in this case we don't have to give it a name.
    //         .root_source_file = b.path("src/4-unusual-database/main.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         // List of modules available for import in source files part of the
    //         // root module.
    //     }),
    // });
    // b.installArtifact(unusual_database_tests);
    //
    // // 5 Mob in the Middle
    // const mob_in_them_middle = b.addExecutable(.{
    //     .name = "mob-in-the-middle",
    //     .root_module = b.createModule(.{
    //         // b.createModule defines a new module just like b.addModule but,
    //         // unlike b.addModule, it does not expose the module to consumers of
    //         // this package, which is why in this case we don't have to give it a name.
    //         .root_source_file = b.path("src/5-mob-in-the-middle/main.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         // List of modules available for import in source files part of the
    //         // root module.
    //     }),
    // });
    // b.installArtifact(mob_in_them_middle);
    //
    // // 4 Unusual Database Program
    // // const mob_in_them_middle_tests = b.addTest(.{
    // //     .name = "mob-in-the-middle-tests",
    // //     .root_module = b.createModule(.{
    // //         // b.createModule defines a new module just like b.addModule but,
    // //         // unlike b.addModule, it does not expose the module to consumers of
    // //         // this package, which is why in this case we don't have to give it a name.
    // //         .root_source_file = b.path("src/5-mob-in-the-middle/main.zig"),
    // //         .target = target,
    // //         .optimize = optimize,
    // //         // List of modules available for import in source files part of the
    // //         // root module.
    // //     }),
    // // });
    // // b.installArtifact(mob_in_them_middle_tests);

    // 6 Speed Daemon
    const speed_daemon = b.addExecutable(.{
        .name = "speed-daemon",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/6-speed-daemon/main.zig"),
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "zig_test" is the name you will use in your source code to
                // import this module (e.g. `@import("zig_test")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "ziglangSet", .module = ziglangSet.module("ziglangSet") },
            },
        }),
    });
    // speed_daemon.root_module.addImport("ziglangSet", ziglangSet.module("ziglangSet"));
    b.installArtifact(speed_daemon);

    // 6 Speed Daemon
    // const speed_daemon_tests = b.addTest(.{
    //     .name = "speed-daemon-tests",
    //     // .root_source_file = b.path("src/6-speed-daemon/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // speed_daemon_tests.root_module.addImport("ziglangSet", ziglangSet.module("ziglangSet"));
    // b.installArtifact(speed_daemon_tests);
}
