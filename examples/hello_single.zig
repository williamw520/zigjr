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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    {
        // Create a registry for the JSON-RPC registry.
        var registry = zigjr.RpcRegistry.init(alloc);
        defer registry.deinit();

        // Register each RPC method with a handling function.
        try registry.add("hello", hello);
        try registry.add("hello-name", helloName);
        try registry.add("hello-xtimes", helloXTimes);
        try registry.add("say", say);

        // RequestDispatcher interface implemented by the 'registry' registry.
        const dispatcher = zigjr.RequestDispatcher.implBy(&registry);
        var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
        defer pipeline.deinit();

        // Read a JSON-RPC request JSON from StdIn.
        const request = try std.io.getStdIn().reader().readAllAlloc(alloc, 64*1024);
        if (request.len > 0) {
            defer alloc.free(request);
            std.debug.print("Request:  {s}\n", .{request});

            // Dispatch the JSON-RPC request to the handler, with result in response JSON.
            if (try pipeline.runRequestToJson(request)) |response| {
                defer alloc.free(response);
                std.debug.print("Response: {s}\n", .{response});
            } else {
                std.debug.print("No response\n", .{});
            }
        } else {
            usage();
        }
    }

    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
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
    var buf = std.ArrayList(u8).init(alloc);
    var writer = buf.writer();
    for (0..repeat) |_| try writer.print("Hello {s}! ", .{name});
    return buf.items;
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



