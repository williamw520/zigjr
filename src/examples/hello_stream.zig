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
        // Create a registry for the JSON-RPC handlers.
        var handlers = zigjr.RpcRegistry.init(alloc);
        defer handlers.deinit();

        // Register each RPC method with a handling function.
        try handlers.register("hello", null, hello);
        try handlers.register("hello-name", null, helloName);
        try handlers.register("say", null, say);

        // Read a stream of JSON requests from the reader, handle each with handlers,
        // and write JSON responses to the writer.  Request frames are delimited by '\n'.
        const streamer = zigjr.DelimiterStream.init(alloc, .{});
        try streamer.streamRequests(std.io.getStdIn().reader(),
                                    std.io.getStdOut().writer(),
                                    handlers);
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

fn say(msg: [] const u8) void {
    std.debug.print("Message to say: {s}\n", .{msg});
}


fn usage() void {
    std.debug.print(
        \\Usage:  hello_stream
        \\Usage:  hello_stream < messages.json
        \\
        \\The program reads from stdin.
        , .{});
}



