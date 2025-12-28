const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create zobject module
    const zobject_module = b.addModule("zobject", .{
        .root_source_file = b.path("src/zobject.zig"),
    });

    // Test setup
    const test_step = b.step("test", "Run all tests");

    // Test files
    const test_files = [_][]const u8{
        "tests/basic_test.zig",
        "tests/static_test.zig",
        "tests/descriptor_test.zig",
        "tests/prototype_test.zig",
        "tests/iteration_test.zig",
    };

    // Add each test file
    inline for (test_files) |test_file| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
            }),
        });

        unit_tests.root_module.addImport("zobject", zobject_module);

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    // Main zobject tests
    const zobject_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zobject.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_zobject_tests = b.addRunArtifact(zobject_tests);
    test_step.dependOn(&run_zobject_tests.step);

    // Make test the default step
    b.default_step = test_step;
}
