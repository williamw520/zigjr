// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;

const zigjr = @import("zigjr");


pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Create a registry for the JSON-RPC registry.
    var rpc_dispatcher = try zigjr.RpcDispatcher.init(alloc);
    defer rpc_dispatcher.deinit();

    // Register each RPC method with a handling function.
    try rpc_dispatcher.add("hello", hello);
    try rpc_dispatcher.add("hello-name", helloName);
    try rpc_dispatcher.add("hello-xtimes", helloXTimes);
    try rpc_dispatcher.add("say", say);

    // RequestDispatcher interface implemented by the 'registry' registry.
    const dispatcher = zigjr.RequestDispatcher.implBy(&rpc_dispatcher);
    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
    defer pipeline.deinit();

    // Read a JSON-RPC request JSON from StdIn.
    var stdin_buffer: [256]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    var read_buf = std.Io.Writer.Allocating.init(alloc);
    defer read_buf.deinit();
    const read_len = stdin.streamDelimiter(&read_buf.writer, '\n') catch |err| blk: {
        switch (err) {
            std.Io.Reader.StreamError.EndOfStream => break :blk read_buf.written().len,
            else => return err,
        }
    };
    if (read_len > 0) {
        std.debug.print("Request:  {s}\n", .{read_buf.written()});

        // Dispatch the JSON-RPC request to the handler, with result in response JSON.
        if (try pipeline.runRequestToJson(alloc, read_buf.written())) |response| {
            defer alloc.free(response);
            std.debug.print("Response: {s}\n", .{response});
        } else {
            std.debug.print("No response\n", .{});
        }
    } else {
        usage();
    }
}


fn hello() []const u8 {
    return "Hello world";
}

fn helloName(alloc: Allocator, name: [] const u8) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "Hello {s}", .{name});
}

fn helloXTimes(alloc: Allocator, name: [] const u8, times: i64) ![]const u8 {
    const repeat: usize = if (0 < times and times < 100) @intCast(times) else 1;
    var buf = std.Io.Writer.Allocating.init(alloc);
    var writer = &buf.writer;
    for (0..repeat) |_| try writer.print("Hello {s}! ", .{name});
    return buf.written();
}

fn say(msg: [] const u8) void {
    std.debug.print("Message to say: {s}\n", .{msg});
}


fn usage() void {
    std.debug.print(
        \\Usage:  hello_single
        \\Usage:  hello_single < message.json
        \\
        \\The program reads from stdin.
        , .{});
}



