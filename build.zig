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

    // Building examples

    const commonOptions = std.Build.Module.CreateOptions {
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    };

    var hello_opt = commonOptions;
    hello_opt.root_source_file = b.path("examples/hello.zig");
    const hello_mod = b.createModule(hello_opt);
    hello_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "hello", .root_module = hello_mod }));

    var hello_single_opt = commonOptions;
    hello_single_opt.root_source_file = b.path("examples/hello_single.zig");
    const hello_single_mod = b.createModule(hello_single_opt);
    hello_single_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "hello_single", .root_module = hello_single_mod }));

    var calc_opt = commonOptions;
    calc_opt.root_source_file = b.path("examples/calc.zig");
    const calc_mod = b.createModule(calc_opt);
    calc_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "calc", .root_module = calc_mod }));

    var stream_calc_opt = commonOptions;
    stream_calc_opt.root_source_file = b.path("examples/stream_calc.zig");
    const stream_calc_mod = b.createModule(stream_calc_opt);
    stream_calc_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "stream_calc", .root_module = stream_calc_mod }));

    var dispatcher_hello_opt = commonOptions;
    dispatcher_hello_opt.root_source_file = b.path("examples/dispatcher_hello.zig");
    const dispatcher_hello_mod = b.createModule(dispatcher_hello_opt);
    dispatcher_hello_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "dispatcher_hello", .root_module = dispatcher_hello_mod }));

    // var dispatcher_counter_opt = commonOptions;
    // dispatcher_counter_opt.root_source_file = b.path("examples/dispatcher_counter.zig");
    // const dispatcher_counter_mod = b.createModule(dispatcher_counter_opt);
    // dispatcher_counter_mod.addImport("zigjr", zigjr_mod);
    // b.installArtifact(b.addExecutable(.{ .name = "dispatcher_counter", .root_module = dispatcher_counter_mod }));

    // var mcp_hello_opt = commonOptions;
    // mcp_hello_opt.root_source_file = b.path("examples/mcp_hello.zig");
    // const mcp_hello_mod = b.createModule(mcp_hello_opt);
    // mcp_hello_mod.addImport("zigjr", zigjr_mod);
    // b.installArtifact(b.addExecutable(.{ .name = "mcp_hello", .root_module = mcp_hello_mod }));

    // var lsp_client_opt = commonOptions;
    // lsp_client_opt.root_source_file = b.path("examples/lsp_client.zig");
    // const lsp_client_mod = b.createModule(lsp_client_opt);
    // lsp_client_mod.addImport("zigjr", zigjr_mod);
    // b.installArtifact(b.addExecutable(.{ .name = "lsp_client", .root_module = lsp_client_mod }));

    // End of building examples

    const lib_unit_tests = b.addTest(.{ .root_module = zigjr_mod });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
