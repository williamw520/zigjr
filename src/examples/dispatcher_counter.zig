// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const stringifyAlloc = std.json.stringifyAlloc;

const zigjr = @import("zigjr");
const RpcRequest = zigjr.RpcRequest;
const DispatchResult = zigjr.DispatchResult;
const ErrorCode = zigjr.ErrorCode;


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    {
        // RequestDispatcher interface implemented by the custom dispatcher.
        var dispatcher_impl = CounterDispatcher{};
        const dispatcher = zigjr.RequestDispatcher.impl_by(&dispatcher_impl);

        const streamer = zigjr.DelimiterStream.init(alloc, .{});
        try streamer.streamRequests(std.io.getStdIn().reader(), std.io.getStdOut().writer(), dispatcher);
    }

    if (gpa.detectLeaks()) { std.debug.print("Memory leak detected!\n", .{}); }
}


const CounterDispatcher = struct {
    count:  isize = 1,                      // start with 1.
    
    pub fn dispatch(self: *@This(), alloc: Allocator, req: RpcRequest) !DispatchResult {
        if (std.mem.eql(u8, req.method, "inc")) {
            self.count += 1;
            return DispatchResult.asNone(); // treat request as notification
        } else if (std.mem.eql(u8, req.method, "dec")) {
            self.count -= 1;
            return DispatchResult.asNone(); // treat request as notification
        } else if (std.mem.eql(u8, req.method, "get")) {
            return DispatchResult.withResult(try stringifyAlloc(alloc, self.count, .{}));
        } else {
            return DispatchResult.withErr(ErrorCode.MethodNotFound, "");
        }
    }

    pub fn dispatchEnd(_: *@This(), alloc: Allocator, _: RpcRequest, dresult: DispatchResult) void {
        switch (dresult) {
            .result => alloc.free(dresult.result),
            else => {},
        }
    }
};


fn usage() void {
    std.debug.print(
        \\Usage:  dispatcher_counter
        \\Usage:  dispatcher_counter < message.json
        \\
        \\The program reads from stdin.
        , .{});
}



