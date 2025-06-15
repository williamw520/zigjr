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
        try handlers.register("hello-xtimes", null, helloXTimes);
        try handlers.register("say", null, say);

        // Read requests from stdin, dispatch to handlers, and write responses to stdout.
        // Request frames are delimited by '\n'.
        const streamer = zigjr.DelimiterStream.init(alloc, .{});
        try streamer.streamRequests(std.io.getStdIn().reader(),
                                    std.io.getStdOut().writer(),
                                    handlers);
    }

    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
    }    
}


// A handler with no parameter and returns a string.
fn hello() []const u8 {
    return "Hello world";
}

// A handler takes in a string parameter and returns a string with error.
// It also asks the library for an allocator, which is passed in automatically.
// Allocated memory is freed automatically, making memory usage simple.
fn helloName(alloc: Allocator, name: [] const u8) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "Hello {s}", .{name});
}

// This one takes one more parameter. Note that i64 is JSON's integer type.
fn helloXTimes(alloc: Allocator, name: [] const u8, times: i64) ![]const u8 {
    const repeat: usize = if (0 < times and times < 100) @intCast(times) else 1;
    var buf = std.ArrayList(u8).init(alloc);
    var writer = buf.writer();
    for (0..repeat) |_| try writer.print("Hello {s}! ", .{name});
    return buf.items;
}

// A handler takes in a string and has no return value, for RPC notification.
fn say(msg: [] const u8) void {
    std.debug.print("Message to say: {s}\n", .{msg});
}


fn usage() void {
    std.debug.print(
        \\Usage:  hello
        \\Usage:  hello < messages.json
        \\
        \\The program reads from stdin.
        , .{});
}



