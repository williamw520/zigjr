const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;

const zigjr = @import("../zigjr.zig");
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
            .result = try std.json.Stringify.valueAlloc(alloc, params.items[0].string, .{}),
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
            return .{ .result = try std.json.Stringify.valueAlloc(alloc, self.count, .{}) };
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
        var reader = std.Io.Reader.fixed(req_jsons);

        var writer_buf = std.Io.Writer.Allocating.init(alloc);
        defer writer_buf.deinit();
        // var logger = zigjr.DbgLogger{};
        try zigjr.stream.requestsByDelimiter(alloc, &reader, &writer_buf.writer, RequestDispatcher.implBy(&dispatcher),
                                             // .{ .logger = zigjr.Logger.implBy(&logger) });
                                             .{});
        // std.debug.print("response_jsons: ##\n{s}##\n", .{writer_buf.written()});
        try testing.expectEqualSlices(u8, writer_buf.written(),
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
        const req_json_list = [_][]const u8{
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
        var req_writer = try zigjr.frame.allocContentLengthFrames(alloc, &req_json_list);
        defer req_writer.deinit();
        // std.debug.print("frames: |{s}|\n", .{req_writer.written()});

        var reader = std.Io.Reader.fixed(req_writer.written());
        var writer_buf = std.Io.Writer.Allocating.init(alloc);
        defer writer_buf.deinit();
        // var logger = zigjr.DbgLogger{};
        try zigjr.stream.requestsByContentLength(alloc, &reader, &writer_buf.writer,
                                                 RequestDispatcher.implBy(&dispatcher),
                                                 // .{ .logger = zigjr.Logger.implBy(&logger) });
                                                 .{});
        // std.debug.print("response_jsons: ##\n{s}##\n", .{writer_buf.written()});
        try testing.expectEqualSlices(u8, writer_buf.written(),
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
        var reader = std.Io.Reader.fixed(req_jsons);

        var writer_buf = std.Io.Writer.Allocating.init(alloc);
        defer writer_buf.deinit();
        // var logger = zigjr.DbgLogger{};
        try zigjr.stream.requestsByDelimiter(alloc, &reader, &writer_buf.writer, RequestDispatcher.implBy(&dispatcher),
                                             // .{ .logger = zigjr.Logger.implBy(&logger) });
                                             .{});

        // std.debug.print("response_jsons: ##\n{s}##\n", .{writer_buf.written()});
        try testing.expectEqualSlices(u8, writer_buf.written(),
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
        var reader = std.Io.Reader.fixed(req_jsons);

        var writer_buf = std.Io.Writer.Allocating.init(alloc);
        defer writer_buf.deinit();
        // var logger = zigjr.DbgLogger{};
        try zigjr.stream.requestsByDelimiter(alloc, &reader, &writer_buf.writer, RequestDispatcher.implBy(&dispatcher), .{
            // .logger = zigjr.Logger.implBy(&logger),
            .skip_blank_message = false });
        // std.debug.print("response_jsons: ##\n{s}##\n", .{writer_buf.written()});
        try testing.expectEqualSlices(u8, writer_buf.written(),
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
        var req_frames = std.Io.Writer.Allocating.init(alloc);
        defer req_frames.deinit();
        try req_frames.writer.writeAll("abcdesdf\r\n");
        try zigjr.frame.writeContentLengthFrames(&req_frames.writer, &req_jsons1);
        try req_frames.writer.writeAll("sdfadf: sdfads\r\n");
        try zigjr.frame.writeContentLengthFrames(&req_frames.writer, &req_jsons2);
        try req_frames.writer.writeAll("\r\n\r\n\r\n\r\n");
        try zigjr.frame.writeContentLengthFrames(&req_frames.writer, &req_jsons3);
        try req_frames.writer.writeAll("sdfadf: sdfads\r\n");
        // std.debug.print("frames: |{s}|\n", .{req_frames.written()});

        var reader = std.Io.Reader.fixed(req_frames.written());
        var writer_buf = std.Io.Writer.Allocating.init(alloc);
        defer writer_buf.deinit();
        // var logger = zigjr.DbgLogger{};
        try zigjr.stream.requestsByContentLength(alloc, &reader, &writer_buf.writer,
                                                 RequestDispatcher.implBy(&dispatcher),
                                                 // .{ .logger = zigjr.Logger.implBy(&logger) });
                                                 .{});
        // std.debug.print("response_jsons: ##\n{s}##\n", .{writer_buf.written()});
        
        try testing.expectEqualSlices(u8, writer_buf.written(),
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
        var reader = std.Io.Reader.fixed(req_jsons);

        var writer_buf = std.Io.Writer.Allocating.init(alloc);
        defer writer_buf.deinit();

        try zigjr.stream.requestsByDelimiter(alloc, &reader, &writer_buf.writer, RequestDispatcher.implBy(&dispatcher), .{});
        // std.debug.print("response_jsons: ##\n{s}##\n", .{writer_buf.written()});
        try testing.expectEqualSlices(u8, writer_buf.written(),
                                      \\{"jsonrpc": "2.0", "result": "abc", "id": "5a"}
                                      \\{"jsonrpc": "2.0", "result": "xyz", "id": "5b"}
                                      \\{"jsonrpc": "2.0", "id": "5c", "error": {"code": -32602, "message": "InvalidParams"}}
                                      \\
                                      );

        var my_response_dispatcher = struct {
            called: bool = false,
            pub fn dispatch(self: *@This(), _: Allocator, res: zigjr.RpcResponse) !void {
                self.called = true;
                // std.debug.print("RpcResponse: {any}\n", .{res});
                if (res.id.eql("5a"))
                    try testing.expectEqualSlices(u8, res.result.string, "abc");
                if (res.id.eql("5b"))
                    try testing.expectEqualSlices(u8, res.result.string, "xyz");
                if (res.id.eql("5c"))
                    try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.InvalidParams));
            }
        } {};

        var response_reader = std.Io.Reader.fixed(writer_buf.written());
        try zigjr.stream.responsesByDelimiter(alloc, &response_reader,
                                              zigjr.ResponseDispatcher.implBy(&my_response_dispatcher), .{});
        try testing.expect(my_response_dispatcher.called);
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
        var req_frames = std.Io.Writer.Allocating.init(alloc);
        defer req_frames.deinit();
        try zigjr.frame.writeContentLengthFrames(&req_frames.writer, &req_jsons);

        var reader = std.Io.Reader.fixed(req_frames.written());
        var writer_buf = std.Io.Writer.Allocating.init(alloc);
        defer writer_buf.deinit();
        try zigjr.stream.requestsByContentLength(alloc, &reader, &writer_buf.writer,
                                                 RequestDispatcher.implBy(&dispatcher), .{});
        // std.debug.print("request_jsons: ##\n{s}##\n", .{write_buffer.items});

        try testing.expectEqualSlices(u8, writer_buf.written(),
            \\Content-Length: 40
                ++ "\r\n\r\n" ++
            \\{"jsonrpc": "2.0", "result": 1, "id": 2}Content-Length: 84
                ++ "\r\n\r\n" ++
            \\{"jsonrpc": "2.0", "id": 99, "error": {"code": -32601, "message": "MethodNotFound"}}Content-Length: 40
                ++ "\r\n\r\n" ++
            \\{"jsonrpc": "2.0", "result": 0, "id": 4}
        );

        var my_response_dispatcher = struct {
            called: bool = false,
            pub fn dispatch(self: *@This(), _: Allocator, res: zigjr.RpcResponse) !void {
                self.called = true;
                // std.debug.print("RpcResponse: {any}\n", .{res});
                if (res.id.eql(2))
                    try testing.expectEqual(res.result.integer, 1);
                if (res.id.eql(4))
                    try testing.expectEqual(res.result.integer, 0);
                if (res.id.eql(99))
                    try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.MethodNotFound));
            }
        } {};

        var response_reader = std.Io.Reader.fixed(writer_buf.written());
        try zigjr.stream.responsesByDelimiter(alloc, &response_reader,
                                              zigjr.ResponseDispatcher.implBy(&my_response_dispatcher), .{});
        try testing.expect(my_response_dispatcher.called);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


