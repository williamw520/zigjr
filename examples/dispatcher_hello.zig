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
const RpcRequest = zigjr.RpcRequest;
const DispatchResult = zigjr.DispatchResult;
const ErrorCode = zigjr.ErrorCode;


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    {
        var stdin_buffer: [1024]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
        const stdin = &stdin_reader.interface;

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        // RequestDispatcher interface implemented by the custom dispatcher.
        var dispatcher_impl = HelloDispatcher{};
        const dispatcher = zigjr.RequestDispatcher.implBy(&dispatcher_impl);
        try zigjr.stream.requestsByDelimiter(alloc, stdin, stdout, dispatcher, .{});
    }

    if (gpa.detectLeaks()) { std.debug.print("Memory leak detected!\n", .{}); }    
}


const HelloDispatcher = struct {
    // The JSON-RPC request has been parsed into a RpcRequest.  Dispatch on it here.
    pub fn dispatch(_: @This(), alloc: Allocator, req: RpcRequest) !DispatchResult {
        if (std.mem.eql(u8, req.method, "hello")) {
            // Result needs to be in JSON.
            return DispatchResult.withResult(try std.json.Stringify.valueAlloc(alloc, "Hello World", .{}));
        } else if (std.mem.eql(u8, req.method, "hello-name")) {
            if (req.params == .array) {
                const items = req.params.array.items;
                if (items.len > 0 and items[0] == .string) {
                    const result = try std.fmt.allocPrint(alloc, "Hello {s}", .{ items[0].string });
                    defer alloc.free(result);
                    return DispatchResult.withResult(try std.json.Stringify.valueAlloc(alloc, result, .{}));
                }
            }
            return DispatchResult.withErr(ErrorCode.InvalidParams, "Invalid params.");
        } else if (std.mem.eql(u8, req.method, "hello-xtimes")) {
            if (req.params == .array) {
                const items = req.params.array.items;
                if (items.len > 1 and items[0] == .string and items[1] == .integer) {
                    const result = try std.fmt.allocPrint(alloc, "Hello {s} X {} times",
                                                          .{ items[0].string, items[1].integer });
                    defer alloc.free(result);
                    return DispatchResult.withResult(try std.json.Stringify.valueAlloc(alloc, result, .{}));
                }
            }
            return DispatchResult.withErr(ErrorCode.InvalidParams, "Invalid params.");
        } else if (std.mem.eql(u8, req.method, "say")) {
            if (req.params == .array) {
                const items = req.params.array.items;
                if (items.len > 0 and items[0] == .string) {
                    std.debug.print("Say: {s}\n", .{items[0].string});
                }
            }
            return DispatchResult.asNone();
        } else {
            return DispatchResult.withErr(ErrorCode.MethodNotFound, "Method not found.");
        }
    }

    // The result has been processed; this call is the chance to clean up DispatchResult.
    pub fn dispatchEnd(_: @This(), alloc: Allocator, _: RpcRequest, dresult: DispatchResult) void {
        // If alloc passed in to runRequestToJson() above is set up as an ArenaAllocator,
        // no need to free memory here.
        switch (dresult) {
            .none => {},
            .result => |result| alloc.free(result),
            .err => {},
        }
    }
};


fn usage() void {
    std.debug.print(
        \\Usage:  dispatcher_hello
        \\Usage:  dispatcher_hello < message.json
        \\
        \\The program reads from stdin.
        , .{});
}



