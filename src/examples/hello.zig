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

        const request = try std.io.getStdIn().reader().readAllAlloc(alloc, 64*1024);
        if (request.len > 0) {
            defer alloc.free(request);
            std.debug.print("Request:  {s}\n", .{request});

            // Dispatch the JSON-RPC request to the handler, with result in response JSON.
            if (try zigjr.handleRequestToJson(alloc, request, handlers)) |response| {
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

fn say(msg: [] const u8) void {
    std.debug.print("Message to say: {s}\n", .{msg});
}


fn usage() void {
    std.debug.print(
        \\Usage:  hello
        \\Usage:  hello < message.json
        \\
        \\The program reads from stdin.
        , .{});
}



