const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;

const zigjr = @import("zigjr");
const ErrorCode = zigjr.ErrorCode;
const RequestDispatcher = zigjr.RequestDispatcher;
const DispatchResult = zigjr.DispatchResult;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const EchoDispatcher = struct {
    pub fn dispatch(_: *@This(), alloc: Allocator, req: zigjr.RpcRequest) !DispatchResult {
        const params = req.arrayParams() orelse
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        if (params.items.len != 1 or params.items[0] != .string) {
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        }
        return .{
            .result = try std.json.stringifyAlloc(alloc, params.items[0].string, .{}),
        };
    }

    pub fn dispatchEnd(_: *@This(), alloc: Allocator, _: zigjr.RpcRequest, dresult: DispatchResult) void {
        switch (dresult) {
            .none => {},
            .result => |json| alloc.free(json),
            .err => {},
        }
    }
};

const CounterDispatcher = struct {
    count:  isize = 0,

    pub fn dispatch(self: *@This(), alloc: Allocator, req: zigjr.RpcRequest) !DispatchResult {
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

    pub fn dispatchEnd(_: *@This(), alloc: Allocator, _: zigjr.RpcRequest, dresult: DispatchResult) void {
        switch (dresult) {
            .result => alloc.free(dresult.result),
            else => {},
        }
    }
};

test "DelimiterStream.streamRequests on JSON requests, single param, id" {
    const alloc = gpa.allocator();
    {
        var dispatcher = EchoDispatcher{};

        const req_jsons =
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["abc"], "id": "5a"}
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["xyz"],  "id": "5b"}
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5c"}
            \\
        ;
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        var json_stream = std.io.fixedBufferStream(req_jsons);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();

        // var logger = zigjr.DbgLogger{};
        // try zigjr.stream.requestsByDelimiter(alloc, reader, writer, RequestDispatcher.impl_by(&dispatcher),
        //                            .{ .logger = zigjr.Logger.impl_by(&logger) });
        try zigjr.stream.requestsByDelimiter(alloc, reader, writer, RequestDispatcher.impl_by(&dispatcher), .{});

        // std.debug.print("output_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
                                      \\{"jsonrpc": "2.0", "result": "abc", "id": "5a"}
                                          \\{"jsonrpc": "2.0", "result": "xyz", "id": "5b"}
                                          \\{"jsonrpc": "2.0", "id": "5c", "error": {"code": -32602, "message": "InvalidParams"}}
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
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        const req_frames = try zigjr.frame.writeContentLengthFrames(alloc, &req_jsons);
        defer req_frames.deinit();
        // std.debug.print("frames: |{s}|\n", .{req_frames.items});

        var json_stream = std.io.fixedBufferStream(req_frames.items);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();

        // var logger = zigjr.DbgLogger{};
        // try zigjr.stream.requestsByContentLength(alloc, reader, writer, RequestDispatcher.impl_by(&dispatcher),
        //                                    .{ .logger = zigjr.Logger.impl_by(&logger) });
        try zigjr.stream.requestsByContentLength(alloc, reader, writer, RequestDispatcher.impl_by(&dispatcher), .{});
        // std.debug.print("response_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
                                      \\Content-Length: 40
                                          ++ "\r\n\r\n" ++
                                          \\{"jsonrpc": "2.0", "result": 1, "id": 2}Content-Length: 84
                                          ++ "\r\n\r\n" ++
                                          \\{"jsonrpc": "2.0", "id": 99, "error": {"code": -32601, "message": "MethodNotFound"}}Content-Length: 40
                                          ++ "\r\n\r\n" ++
                                          \\{"jsonrpc": "2.0", "result": 0, "id": 4}
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "DelimiterStream.streamRequests on JSON requests, recover from error" {
    const alloc = gpa.allocator();
    {
        var dispatcher = EchoDispatcher{};

        const req_jsons =
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["abc"], "id": "5a"}
            \\garbage abc
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["xyz"],  "id": "5b"}
            \\
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5c"}
            \\
        ;
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        var json_stream = std.io.fixedBufferStream(req_jsons);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();

        try zigjr.stream.requestsByDelimiter(alloc, reader, writer, RequestDispatcher.impl_by(&dispatcher), .{});
        // std.debug.print("output_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
                                      \\{"jsonrpc": "2.0", "result": "abc", "id": "5a"}
                                          \\{"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "SyntaxError"}}
                                          \\{"jsonrpc": "2.0", "result": "xyz", "id": "5b"}
                                          \\{"jsonrpc": "2.0", "id": "5c", "error": {"code": -32602, "message": "InvalidParams"}}
                                          \\
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "DelimiterStream.streamRequests on JSON requests, no skipping blank lines, recover from error" {
    const alloc = gpa.allocator();
    {
        var dispatcher = EchoDispatcher{};

        const req_jsons =
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["abc"], "id": "5a"}
            \\garbage abc
            \\{"jsonrpc": "2.0", "method": "fun0", "params": ["xyz"],  "id": "5b"}
            \\
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5c"}
            \\
        ;
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        var json_stream = std.io.fixedBufferStream(req_jsons);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();

        try zigjr.stream.requestsByDelimiter(alloc, reader, writer, RequestDispatcher.impl_by(&dispatcher), .{ .skip_blank_message = false });
        // std.debug.print("output_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
                                      \\{"jsonrpc": "2.0", "result": "abc", "id": "5a"}
                                          \\{"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "SyntaxError"}}
                                          \\{"jsonrpc": "2.0", "result": "xyz", "id": "5b"}
                                          \\{"jsonrpc": "2.0", "id": null, "error": {"code": -32600, "message": "UnexpectedEndOfInput"}}
                                          \\{"jsonrpc": "2.0", "id": "5c", "error": {"code": -32602, "message": "InvalidParams"}}
                                          \\
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "ContentLengthStream.streamRequests on JSON requests, recover from missing headers" {
    const alloc = gpa.allocator();
    {
        var dispatcher = CounterDispatcher{};
        const req_jsons1 = [_][]const u8{
            \\{"jsonrpc": "2.0", "method": "inc", "id": 1}
                ,
            \\{"jsonrpc": "2.0", "method": "get", "id": 2}
                ,
        };
        const req_jsons2 = [_][]const u8{
            \\{"jsonrpc": "2.0", "method": "dec", "id": 3}
                ,
            \\{"jsonrpc": "2.0", "method": "no-method", "id": 99}
                ,
        };
        const req_jsons3 = [_][]const u8{
            \\{"jsonrpc": "2.0", "method": "get", "id": 4}
                ,
        };
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        var req_frames = std.ArrayList(u8).init(alloc);
        defer req_frames.deinit();
        const garbage_data1 = "abcdesdf\r\n";
        const valid_frames1 = try zigjr.frame.writeContentLengthFrames(alloc, &req_jsons1);
        const garbage_data2 = "sdfadf: sdfads\r\n";
        const valid_frames2 = try zigjr.frame.writeContentLengthFrames(alloc, &req_jsons2);
        const garbage_data3 = "\r\n\r\n\r\n\r\n";
        const valid_frames3 = try zigjr.frame.writeContentLengthFrames(alloc, &req_jsons3);
        const garbage_data4 = "sdfadf: sdfads\r\n";
        defer valid_frames1.deinit();
        defer valid_frames2.deinit();
        defer valid_frames3.deinit();
        try req_frames.appendSlice(garbage_data1);
        try req_frames.appendSlice(valid_frames1.items);
        try req_frames.appendSlice(garbage_data2);
        try req_frames.appendSlice(valid_frames2.items);
        try req_frames.appendSlice(garbage_data3);
        try req_frames.appendSlice(valid_frames3.items);
        try req_frames.appendSlice(garbage_data4);
        // std.debug.print("frames: |{s}|\n", .{req_frames.items});

        var json_stream = std.io.fixedBufferStream(req_frames.items);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();

        try zigjr.stream.requestsByContentLength(alloc, reader, writer, RequestDispatcher.impl_by(&dispatcher), .{});
        // std.debug.print("response_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
                                      \\Content-Length: 40
                                          ++ "\r\n\r\n" ++
                                          \\{"jsonrpc": "2.0", "result": 1, "id": 2}Content-Length: 84
                                          ++ "\r\n\r\n" ++
                                          \\{"jsonrpc": "2.0", "id": 99, "error": {"code": -32601, "message": "MethodNotFound"}}Content-Length: 40
                                          ++ "\r\n\r\n" ++
                                          \\{"jsonrpc": "2.0", "result": 0, "id": 4}
                                      );
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "DelimiterStream.streamResponses on JSON responses, single param, id" {
    const alloc = gpa.allocator();
    {
        var dispatcher = EchoDispatcher{};

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

        try zigjr.stream.requestsByDelimiter(alloc, reader, writer, RequestDispatcher.impl_by(&dispatcher), .{});
        // std.debug.print("output_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
                                      \\{"jsonrpc": "2.0", "result": "abc", "id": "5a"}
                                          \\{"jsonrpc": "2.0", "result": "xyz", "id": "5b"}
                                          \\{"jsonrpc": "2.0", "id": "5c", "error": {"code": -32602, "message": "InvalidParams"}}
                                          \\
                                      );

        var my_response_dispatcher = struct {
            pub fn dispatch(_: *@This(), _: Allocator, res: zigjr.RpcResponse) !void {
                // std.debug.print("RpcResponse: {any}\n", .{res});
                if (res.id.eql("5a"))
                    try testing.expectEqualSlices(u8, res.result.string, "abc");
                if (res.id.eql("5b"))
                    try testing.expectEqualSlices(u8, res.result.string, "xyz");
                if (res.id.eql("5c"))
                    try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.InvalidParams));
            }
        } {};

        var response_stream = std.io.fixedBufferStream(write_buffer.items);
        const response_reader = response_stream.reader();
        try zigjr.stream.responsesByDelimiter(alloc, response_reader,
                                        zigjr.ResponseDispatcher.impl_by(&my_response_dispatcher), .{});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "responsesByLength on JSON responses, single param, id" {
    const alloc = gpa.allocator();
    {
        var dispatcher = CounterDispatcher{};
        const req_jsons = [_][]const u8{
            \\{"jsonrpc": "2.0", "method": "inc", "id": 1 }
            ,
            \\{"jsonrpc": "2.0", "method": "get", "id": 2 }
            ,
            \\{"jsonrpc": "2.0", "method": "dec", "id": 3 }
            ,
            \\{"jsonrpc": "2.0", "method": "no-method", "id": 99 }
            ,
            \\{"jsonrpc": "2.0", "method": "get", "id": 4 }
            ,
        };
        // std.debug.print("req_jsons: |{s}|\n", .{req_jsons});
        const req_frames = try zigjr.frame.writeContentLengthFrames(alloc, &req_jsons);
        defer req_frames.deinit();
        // std.debug.print("frames: |{s}|\n", .{req_frames.items});

        var json_stream = std.io.fixedBufferStream(req_frames.items);
        const reader = json_stream.reader();

        var write_buffer = ArrayList(u8).init(alloc);
        defer write_buffer.deinit();
        const writer = write_buffer.writer();

        try zigjr.stream.requestsByContentLength(alloc, reader, writer, RequestDispatcher.impl_by(&dispatcher), .{});
        // std.debug.print("request_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, write_buffer.items,
            \\Content-Length: 40
            ++ "\r\n\r\n" ++
            \\{"jsonrpc": "2.0", "result": 1, "id": 2}Content-Length: 84
            ++ "\r\n\r\n" ++
            \\{"jsonrpc": "2.0", "id": 99, "error": {"code": -32601, "message": "MethodNotFound"}}Content-Length: 40
            ++ "\r\n\r\n" ++
            \\{"jsonrpc": "2.0", "result": 0, "id": 4}
        );

        var my_response_dispatcher = struct {
            pub fn dispatch(_: *@This(), _: Allocator, res: zigjr.RpcResponse) !void {
                // std.debug.print("RpcResponse: {any}\n", .{res});
                if (res.id.eql(2))
                    try testing.expectEqual(res.result.integer, 1);
                if (res.id.eql(4))
                    try testing.expectEqual(res.result.integer, 0);
                if (res.id.eql(99))
                    try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.MethodNotFound));
            }
        } {};
        
        var response_stream = std.io.fixedBufferStream(write_buffer.items);
        const response_reader = response_stream.reader();
        try zigjr.stream.responsesByContentLength(alloc, response_reader,
                                            zigjr.ResponseDispatcher.impl_by(&my_response_dispatcher), .{});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}
