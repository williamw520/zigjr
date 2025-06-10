const std = @import("std");


pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip_debug_symbols = b.option(bool, "strip", "strip debugging symbols") orelse false;

    const zigjr_mod = b.addModule("zigjr", .{
        .root_source_file = b.path("src/zigjr.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });

    const cli_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/zigjr-cli.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });
    cli_exe_mod.addImport("zigjr", zigjr_mod);

    const cli_exe = b.addExecutable(.{
        .name = "zigjr-cli",
        .root_module = cli_exe_mod,
    });
    b.installArtifact(cli_exe);

    const run_cmd = b.addRunArtifact(cli_exe);


    const example_calc_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/calc.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });
    example_calc_mod.addImport("zigjr", zigjr_mod);

    const example_calc_exe = b.addExecutable(.{
        .name = "calc",
        .root_module = example_calc_mod,
    });
    b.installArtifact(example_calc_exe);

    const example_hello_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/hello.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });
    example_hello_mod.addImport("zigjr", zigjr_mod);

    const example_hello_exe = b.addExecutable(.{
        .name = "hello",
        .root_module = example_hello_mod,
    });
    b.installArtifact(example_hello_exe);


    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = zigjr_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = cli_exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
