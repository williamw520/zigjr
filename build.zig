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


    // Building examples

    const hello_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/hello.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });
    hello_mod.addImport("zigjr", zigjr_mod);

    const hello_exe = b.addExecutable(.{
        .name = "hello",
        .root_module = hello_mod,
    });
    b.installArtifact(hello_exe);

    const calc_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/calc.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });
    calc_mod.addImport("zigjr", zigjr_mod);

    const calc_exe = b.addExecutable(.{
        .name = "calc",
        .root_module = calc_mod,
    });
    b.installArtifact(calc_exe);

    const calc_stream_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/calc_stream.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });
    calc_stream_mod.addImport("zigjr", zigjr_mod);

    const calc_stream_exe = b.addExecutable(.{
        .name = "calc_stream",
        .root_module = calc_stream_mod,
    });
    b.installArtifact(calc_stream_exe);

    const dispatcher_hello_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/dispatcher_hello.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });
    dispatcher_hello_mod.addImport("zigjr", zigjr_mod);

    const dispatcher_hello_exe = b.addExecutable(.{
        .name = "dispatcher_hello",
        .root_module = dispatcher_hello_mod,
    });
    b.installArtifact(dispatcher_hello_exe);

    // End of building examples

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
