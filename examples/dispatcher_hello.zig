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
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // RequestDispatcher interface implemented by the custom dispatcher HelloDispatcher.
    var hello_dispatcher = HelloDispatcher{ .alloc = alloc };
    const dispatcher = zigjr.RequestDispatcher.implBy(&hello_dispatcher);

    // Construct a pipeline with the custom dispatcher.
    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
    defer pipeline.deinit();

    // Read request from stdin.
    var read_buf = std.Io.Writer.Allocating.init(alloc);
    defer read_buf.deinit();
    const read_len = stdin.streamDelimiter(&read_buf.writer, '\n') catch |err| blk: {
        switch (err) {
            std.Io.Reader.StreamError.EndOfStream => break :blk read_buf.written().len,
            else => return err,
        }
    };
    
    if (read_len > 0) {
        try stdout.print("Request:  {s}\n", .{read_buf.written()});

        // Run request through the pipeline.
        if (try pipeline.runRequestToJson(alloc, read_buf.written())) |response| {
            defer alloc.free(response);
            try stdout.print("Response: {s}\n", .{response});
        } else {
            try stdout.print("No response\n", .{});
        }
        try stdout.flush();
    } else {
        usage();
    }
    
}


const HelloDispatcher = struct {
    alloc:  Allocator,

    // The JSON-RPC request has been parsed into a RpcRequest.  Dispatch on it here.
    pub fn dispatch(self: @This(), req: RpcRequest) !DispatchResult {
        if (std.mem.eql(u8, req.method, "hello")) {
            // Result needs to be in JSON.
            return DispatchResult.withResult(try std.json.Stringify.valueAlloc(self.alloc, "Hello World", .{}));
        } else if (std.mem.eql(u8, req.method, "hello-name")) {
            if (req.params == .array) {
                const items = req.params.array.items;
                if (items.len > 0 and items[0] == .string) {
                    const result = try std.fmt.allocPrint(self.alloc, "Hello {s}", .{ items[0].string });
                    defer self.alloc.free(result);
                    return DispatchResult.withResult(try std.json.Stringify.valueAlloc(self.alloc, result, .{}));
                }
            }
            return DispatchResult.withErr(ErrorCode.InvalidParams, "Invalid params.");
        } else if (std.mem.eql(u8, req.method, "hello-xtimes")) {
            if (req.params == .array) {
                const items = req.params.array.items;
                if (items.len > 1 and items[0] == .string and items[1] == .integer) {
                    const result = try std.fmt.allocPrint(self.alloc, "Hello {s} X {} times",
                                                          .{ items[0].string, items[1].integer });
                    defer self.alloc.free(result);
                    return DispatchResult.withResult(try std.json.Stringify.valueAlloc(self.alloc, result, .{}));
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
    pub fn dispatchEnd(self: @This(), _: RpcRequest, dresult: DispatchResult) void {
        // If alloc passed in to runRequestToJson() above is set up as an ArenaAllocator,
        // no need to free memory here.
        switch (dresult) {
            .none => {},
            .result => |result| self.alloc.free(result),
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



