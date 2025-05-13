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
const RunResult = zigjr.RunResult;

const stream = @import("../streaming/stream.zig");
const frame = @import("../streaming/frame.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const EchoDispatcher = struct {
    pub fn run(alloc: Allocator, req: RpcRequest) !RunResult {
        const params = req.arrayParams() orelse
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        if (params.items.len != 1 or params.items[0] != .string) {
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        }
        return .{
            .result = try std.json.stringifyAlloc(alloc, params.items[0].string, .{}),
        };
    }

    pub fn free(alloc: Allocator, dresult: RunResult) void {
        switch (dresult) {
            .none => {},
            .result => |json| alloc.free(json),
            .result_lit => {},
            .err => {},
        }
    }
};

const CounterDispatcher = struct {
    count:  isize = 0,
    
    pub fn run(self: *@This(), alloc: Allocator, req: RpcRequest) !RunResult {
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

    pub fn free(_: *@This(), alloc: Allocator, dr: RunResult) void {
        switch (dr) {
            .result => alloc.free(dr.result),
            else => {},
        }
    }
};

const ResponseDispatcher = struct {
    pub fn run(_: Allocator, res: zigjr.RpcResponse) !void {
        std.debug.print("RpcResponse: {any}\n", .{res});
    }
};


test "DelimiterStream.streamRequests on JSON requests, single param, id" {
    const alloc = gpa.allocator();
    {
        const req_jsons = 
            \\{ "jsonrpc": "2.0", "method": "fun0", "params": ["abc"], "id": "5a" }
            \\{ "jsonrpc": "2.0", "method": "fun0", "params": ["xyz"],  "id": "5b" }
            \\{ "jsonrpc": "2.0", "method": "fun0", "id": "5c" }
            \\
        ;
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        var json_stream = std.io.fixedBufferStream(req_jsons);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();
        var buf_writer = std.io.bufferedWriter(writer);

        const streamer = stream.DelimiterStream.init(alloc, .{});
        // const streamer = stream.DelimiterStream.init(alloc, .{ .logger = stream.debugLogger });

        try streamer.streamRequests(reader, &buf_writer, EchoDispatcher);
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

test "ContentLengthStream.streamRequests on JSON requests, single param, id" {
    const alloc = gpa.allocator();
    {
        var dispatcher = CounterDispatcher{};
        const req_jsons = [_][]const u8{
            \\{ "jsonrpc": "2.0", "method": "inc", "id": 1 }
            ,
            \\{ "jsonrpc": "2.0", "method": "get", "id": 2 }
            ,
            \\{ "jsonrpc": "2.0", "method": "dec", "id": 3 }
            ,
            \\{ "jsonrpc": "2.0", "method": "no-method", "id": 99 }
            ,
            \\{ "jsonrpc": "2.0", "method": "get", "id": 4 }
            ,
        };
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        const req_frames = try frame.writeContentLengthFrames(alloc, &req_jsons);
        defer req_frames.deinit();
        // std.debug.print("frames: |{s}|\n", .{req_frames.items});

        var json_stream = std.io.fixedBufferStream(req_frames.items);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();
        var buf_writer = std.io.bufferedWriter(writer);

        const streamer = stream.ContentLengthStream.init(alloc, .{});
        // const streamer = stream.ContentLengthStream.init(alloc, .{ .logger = stream.debugLogger });
        try streamer.streamRequests(reader, &buf_writer, &dispatcher);
        // std.debug.print("response_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
            \\Content-Length: 42
            ++ "\r\n\r\n" ++
            \\{ "jsonrpc": "2.0", "result": 1, "id": 2 }Content-Length: 88
            ++ "\r\n\r\n" ++
            \\{ "jsonrpc": "2.0", "id": 99, "error": { "code": -32601, "message": "MethodNotFound" } }Content-Length: 42
            ++ "\r\n\r\n" ++
            \\{ "jsonrpc": "2.0", "result": 0, "id": 4 }
        );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "DelimiterStream.streamResponses on JSON responses, single param, id" {
    const alloc = gpa.allocator();
    {
        const req_jsons = 
            \\{ "jsonrpc": "2.0", "method": "fun0", "params": ["abc"], "id": "5a" }
            \\{ "jsonrpc": "2.0", "method": "fun0", "params": ["xyz"],  "id": "5b" }
            \\{ "jsonrpc": "2.0", "method": "fun0", "id": "5c" }
            \\
        ;
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        var json_stream = std.io.fixedBufferStream(req_jsons);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();
        var buf_writer = std.io.bufferedWriter(writer);

        const streamer = stream.DelimiterStream.init(alloc, .{});
        // const streamer = stream.DelimiterStream.init(alloc, .{ .logger = stream.debugLogger });

        try streamer.streamRequests(reader, &buf_writer, EchoDispatcher);
        // std.debug.print("output_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
            \\{ "jsonrpc": "2.0", "result": "abc", "id": "5a" }
            \\{ "jsonrpc": "2.0", "result": "xyz", "id": "5b" }
            \\{ "jsonrpc": "2.0", "id": "5c", "error": { "code": -32602, "message": "InvalidParams" } }
            \\
        );

        var response_stream = std.io.fixedBufferStream(write_buffer.items);
        const response_reader = response_stream.reader();
        try streamer.streamResponses(response_reader, struct {
            pub fn run(_: Allocator, res: zigjr.RpcResponse) !void {
                // std.debug.print("RpcResponse: {any}\n", .{res});
                if (res.id.eql("5a"))
                    try testing.expectEqualSlices(u8, res.result.string, "abc");
                if (res.id.eql("5b"))
                    try testing.expectEqualSlices(u8, res.result.string, "xyz");
                if (res.id.eql("5c"))
                    try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.InvalidParams));
            }
        });

    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "responsesByLength on JSON responses, single param, id" {
    const alloc = gpa.allocator();
    {
        var dispatcher = CounterDispatcher{};
        const req_jsons = [_][]const u8{
            \\{ "jsonrpc": "2.0", "method": "inc", "id": 1 }
            ,
            \\{ "jsonrpc": "2.0", "method": "get", "id": 2 }
            ,
            \\{ "jsonrpc": "2.0", "method": "dec", "id": 3 }
            ,
            \\{ "jsonrpc": "2.0", "method": "no-method", "id": 99 }
            ,
            \\{ "jsonrpc": "2.0", "method": "get", "id": 4 }
            ,
        };
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        const req_frames = try frame.writeContentLengthFrames(alloc, &req_jsons);
        defer req_frames.deinit();
        // std.debug.print("frames: |{s}|\n", .{req_frames.items});

        var json_stream = std.io.fixedBufferStream(req_frames.items);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();
        var buf_writer = std.io.bufferedWriter(writer);

        const streamer = stream.ContentLengthStream.init(alloc, .{});
        // const streamer = stream.ContentLengthStream.init(alloc, .{ .logger = stream.debugLogger });
        try streamer.streamRequests(reader, &buf_writer, &dispatcher);
        // std.debug.print("request_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
            \\Content-Length: 42
            ++ "\r\n\r\n" ++
            \\{ "jsonrpc": "2.0", "result": 1, "id": 2 }Content-Length: 88
            ++ "\r\n\r\n" ++
            \\{ "jsonrpc": "2.0", "id": 99, "error": { "code": -32601, "message": "MethodNotFound" } }Content-Length: 42
            ++ "\r\n\r\n" ++
            \\{ "jsonrpc": "2.0", "result": 0, "id": 4 }
        );

        var response_stream = std.io.fixedBufferStream(write_buffer.items);
        const response_reader = response_stream.reader();
        // try stream.responsesByLength(alloc, response_reader, struct {
        try streamer.streamResponses(response_reader, struct {
            pub fn run(_: Allocator, res: zigjr.RpcResponse) !void {
                // std.debug.print("RpcResponse: {any}\n", .{res});
                if (res.id.eql(2))
                    try testing.expectEqual(res.result.integer, 1);
                if (res.id.eql(4))
                    try testing.expectEqual(res.result.integer, 0);
                if (res.id.eql(99))
                    try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.MethodNotFound));
            }
        });

    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



