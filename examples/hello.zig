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
        var registry = zigjr.RpcRegistry.init(alloc);
        defer registry.deinit();

        // Register each RPC method with a handling function.
        try registry.add("hello", hello);
        try registry.add("hello-name", helloName);
        try registry.add("hello-xtimes", helloXTimes);
        try registry.add("substr", substr);
        try registry.add("say", say);

        // Read requests from stdin, dispatch to handlers, and write responses to stdout.
        try zigjr.stream.requestsByDelimiter(alloc,
            std.io.getStdIn().reader(), std.io.getStdOut().writer(),
            zigjr.RequestDispatcher.implBy(&registry), .{});
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
fn helloName(alloc: Allocator, name: [] const u8) std.fmt.AllocPrintError![]const u8 {
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

fn substr(name: [] const u8, start: i64, len: i64) []const u8 {
    return name[@intCast(start) .. @intCast(len)];
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



