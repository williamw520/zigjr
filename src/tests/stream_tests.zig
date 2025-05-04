const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const zigjr = @import("../zigjr.zig");
const RpcRequestMessage = zigjr.RpcRequestMessage;
const RpcRequest = zigjr.RpcRequest;
const ErrorCode = zigjr.ErrorCode;
const JrErrors = zigjr.JrErrors;
const DispatchResult = zigjr.DispatchResult;

const ds = @import("../streaming/delimiter_stream.zig");
const ls = @import("../streaming/length_stream.zig");
const frame = @import("../streaming/frame.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const EchoDispatcher = struct {
    pub fn run(alloc: Allocator, req: RpcRequest) !DispatchResult {
        const params = req.arrayParams() orelse
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        if (params.items.len != 1 or params.items[0] != .string) {
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        }
        return .{
            .result = try std.json.stringifyAlloc(alloc, params.items[0].string, .{}),
        };
    }

    pub fn free(alloc: Allocator, dresult: DispatchResult) void {
        switch (dresult) {
            .result => |json| alloc.free(json),
            .err => {},
            .none => {},
        }
    }
};

const CounterDispatcher = struct {
    count:  isize = 0,
    
    pub fn run(self: *@This(), alloc: Allocator, req: RpcRequest) !DispatchResult {
        if (std.mem.eql(u8, req.method, "inc")) {
            self.count += 1;
            return .{ .none = {} };     // treat request as notification
        } else if (std.mem.eql(u8, req.method, "dec")) {
            self.count -= 1;
            return .{ .none = {} };     // treat request as notification
        } else if (std.mem.eql(u8, req.method, "get")) {
            return .{ .result = try std.json.stringifyAlloc(alloc, self.count, .{}) };
        } else {
            return .{ .err = .{ .code = ErrorCode.MethodNotFound } };
        }
    }

    pub fn free(_: *@This(), alloc: Allocator, dr: DispatchResult) void {
        switch (dr) {
            .result => alloc.free(dr.result),
            else => {},
        }
    }
};


test "streamByDelimiter on JSON requests, single param, id" {
    const alloc = gpa.allocator();
    {
        const req_jsons = 
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["abc"], "id": "5a" }
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["xyz"],  "id": "5b" }
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5c" }
            \\
        ;
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        var json_stream = std.io.fixedBufferStream(req_jsons);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();
        var buf_writer = std.io.bufferedWriter(writer);

        try ds.streamByDelimiter(alloc, '\n', '\n', reader, &buf_writer, EchoDispatcher);
        // std.debug.print("output_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
            \\{ "jsonrpc": "2.0", "result": "abc", "id": "5a" }
            \\{ "jsonrpc": "2.0", "result": "xyz", "id": "5b" }
            \\{ "jsonrpc": "2.0", "id": "5c", "error": { "code": -32602, "message": "InvalidParams" } }
            \\
        );
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "streamByContentLength on JSON requests, single param, id" {
    const alloc = gpa.allocator();
    {
        var dispatcher = CounterDispatcher{};
        const req_jsons = [_][]const u8{
            \\{"jsonrpc": "2.0", "method": "inc", "id": 1}
            ,
            \\{"jsonrpc": "2.0", "method": "get", "id": 2}
            ,
            \\{"jsonrpc": "2.0", "method": "dec", "id": 3}
            ,
            \\{"jsonrpc": "2.0", "method": "no-method", "id": 99}
            ,
            \\{"jsonrpc": "2.0", "method": "get", "id": 4}
            ,
        };
        std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        const req_frames = try frame.writeContentLengthFrames(alloc, &req_jsons);
        defer req_frames.deinit();
        std.debug.print("frames: |{s}|\n", .{req_frames.items});

        var json_stream = std.io.fixedBufferStream(req_frames.items);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();
        var buf_writer = std.io.bufferedWriter(writer);

        try ls.streamByContentLength(alloc, reader, &buf_writer, &dispatcher);
        std.debug.print("response_jsons: ##\n{s}##\n", .{write_buffer.items});

        // try testing.expectEqualSlices(u8, write_buffer.items,
        //     \\{ "jsonrpc": "2.0", "result": "abc", "id": "5a" }
        //     \\{ "jsonrpc": "2.0", "result": "xyz", "id": "5b" }
        //     \\{ "jsonrpc": "2.0", "id": "5c", "error": { "code": -32602, "message": "InvalidParams" } }
        //     \\
        // );
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



