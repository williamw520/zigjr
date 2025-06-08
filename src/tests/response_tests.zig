const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;
const stringifyAlloc = std.json.stringifyAlloc;

const zigjr = @import("../zigjr.zig");
const RpcRequestMessage = zigjr.RpcRequestMessage;
const RpcRequest = zigjr.RpcRequest;
const DispatchResult = zigjr.DispatchResult;
const ErrorCode = zigjr.ErrorCode;
const JrErrors = zigjr.JrErrors;
const DispatchErrors = zigjr.DispatchErrors;


var gpa = std.heap.GeneralPurposeAllocator(.{}){};


const HelloDispatcher = struct {
    pub fn dispatch(_: Allocator, req: RpcRequest) !DispatchResult {
        if (std.mem.eql(u8, req.method, "hello")) {
            return .{
                .result = "\"hello back\"",
            };
        } else {
            return .{
                .err = .{
                    .code = ErrorCode.MethodNotFound,
                    .msg = "Method not found.",
                }
            };
        }
    }

    pub fn dispatchEnd(_: Allocator, _: RpcRequest, dresult: DispatchResult) void {
        // All result data are constant strings.  Nothing to free.
        switch (dresult) {
            .none => {},
            .result => {},
            .err => {},
        }
    }
};

const IntCalcDispatcher = struct {
    pub fn dispatch(alloc: Allocator, req: RpcRequest) !DispatchResult {
        if (req.hasError()) {
            return .withRequestErr(req);
        }
        const params = req.arrayParams() orelse
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        if (params.items.len != 2) {
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        }
        if (params.items[0] != .integer or params.items[1] != .integer) {
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        }

        const a = params.items[0].integer;
        const b = params.items[1].integer;
        var result: i64 = 0;
        if (std.mem.eql(u8, req.method, "add")) {
            result = add(a, b);
        } else if (std.mem.eql(u8, req.method, "sub")) {
            result = sub(a, b);
        } else if (std.mem.eql(u8, req.method, "multiply")) {
            result = multiply(a, b);
        } else if (std.mem.eql(u8, req.method, "divide")) {
            result = divide(a, b);
        } else {
            return .{ .err = .{ .code = ErrorCode.MethodNotFound } };
        }

        return .{
            .result = try stringifyAlloc(alloc, result, .{})
        };
    }

    pub fn dispatchEnd(alloc: Allocator, _: RpcRequest, dresult: DispatchResult) void {
        switch (dresult) {
            .none => {},
            .result => alloc.free(dresult.result),
            .err => {},
        }
    }
    
    fn add(a: i64, b: i64) i64 { return a + b; }
    fn sub(a: i64, b: i64) i64 { return a - b; }
    fn multiply(a: i64, b: i64) i64 { return a * b; }
    fn divide(a: i64, b: i64) i64 { return @divTrunc(a, b); }
};

const FloatCalcDispatcher = struct {
    pub fn dispatch(alloc: Allocator, req: RpcRequest) !DispatchResult {
        const params = req.arrayParams() orelse
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        if (params.items.len != 2) {
            return .{ .err = .{ .code = ErrorCode.InvalidParams } };
        }
        const a = switch (params.items[0]) {
            .float   => |f| f,
            .integer => |n| @as(f64, @floatFromInt(n)),
            else => return .{ .err = .{ .code = ErrorCode.InvalidParams } }
        };
        const b = switch (params.items[1]) {
            .float   => |f| f,
            .integer => |n| @as(f64, @floatFromInt(n)),
            else => return .{ .err = .{ .code = ErrorCode.InvalidParams } }
        };

        var result: f64 = 0;
        if (std.mem.eql(u8, req.method, "add")) {
            result = a + b;
        } else if (std.mem.eql(u8, req.method, "sub")) {
            result = a - b;
        } else if (std.mem.eql(u8, req.method, "multiply")) {
            result = a * b;
        } else if (std.mem.eql(u8, req.method, "divide")) {
            result = a / b;
        } else {
            return .{ .err = .{ .code = ErrorCode.MethodNotFound } };
        }

        return .{
            .result = try stringifyAlloc(alloc, result, .{})
        };
    }

    pub fn dispatchEnd(alloc: Allocator, _: RpcRequest, dresult: DispatchResult) void {
        switch (dresult) {
            .result => alloc.free(dresult.result),
            .err => {},
            else => {},
        }
    }

};

const CounterDispatcher = struct {
    count:  isize = 0,
    
    pub fn dispatch(self: *@This(), alloc: Allocator, req: RpcRequest) !DispatchResult {
        if (std.mem.eql(u8, req.method, "inc")) {
            self.count += 1;
            return .{ .none = {} };     // treat request as notification
        } else if (std.mem.eql(u8, req.method, "dec")) {
            self.count -= 1;
            return .{ .none = {} };     // treat request as notification
        } else if (std.mem.eql(u8, req.method, "get")) {
            return .{ .result = try stringifyAlloc(alloc, self.count, .{}) };
        } else {
            return .{ .err = .{ .code = ErrorCode.MethodNotFound } };
        }
    }

    pub fn dispatchEnd(_: *@This(), alloc: Allocator, _: RpcRequest, dresult: DispatchResult) void {
        switch (dresult) {
            .result => alloc.free(dresult.result),
            else => {},
        }
    }
};


test "Response to a request of hello method" {
    const alloc = gpa.allocator();
    {
        var response_buf = std.ArrayList(u8).init(alloc);
        defer response_buf.deinit();
        _ = try zigjr.handleJsonRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
            , response_buf.writer(), HelloDispatcher);
        // std.debug.print("response: {s}\n", .{response_buf.items});

        var parsed_res = try zigjr.parseRpcResponse(alloc, response_buf.items);
        defer parsed_res.deinit();
        const res = try parsed_res.response();
        // std.debug.print("res.result: {s}\n", .{res.result.string});

        try testing.expectEqualSlices(u8, res.result.string, "hello back");
        try testing.expect(res.resultEql("hello back"));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Handle a request of hello method" {
    const alloc = gpa.allocator();
    {
        const res_json = try zigjr.handleRequestToJson(alloc,
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
        , HelloDispatcher);
        defer if (res_json)|json| alloc.free(json);
        // std.debug.print("response: {s}\n", .{res_json.?});

        var parsed_res = try zigjr.parseRpcResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();
        // std.debug.print("res.result: {s}\n", .{res.result.string});

        try testing.expect(res.resultEql("hello back"));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Handle a request of unknown method, expect error" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "non-hello", "params": [42], "id": 1}
            , HelloDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Handle a request with anonymous dispatcher struct" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
        , struct {
            pub fn dispatch(_: Allocator, _: RpcRequest) !DispatchResult {
                return .{ .result = "\"hello back\"" };
            }
            pub fn dispatchEnd(_: Allocator, _: RpcRequest, dresult: DispatchResult) void {
                switch (dresult) {
                    else => {}
                }
            }
        });
        defer parsed_res.deinit();
        // std.debug.print("res.result: {}\n", .{try parsed_res.response()});

        try testing.expect((try parsed_res.response()).resultEql("hello back"));
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer add" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1, 2], "id": 1}
            , IntCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, 3);
        try testing.expect(res.resultEql(3));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "handleRequestToJson on a request of integer add" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1, 2], "id": 1}
            , IntCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, 3);
        try testing.expect(res.resultEql(3));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer sub" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "sub", "params": [1, 2], "id": 1}
            , IntCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, -1);
        try testing.expect(res.resultEql(-1));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer multiply" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "multiply", "params": [10, 2], "id": 1}
            , IntCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, 20);
        try testing.expect(res.resultEql(20));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer divide" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "divide", "params": [10, 3], "id": 1}
            , IntCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, 3);
        try testing.expect(res.resultEql(3));
        try testing.expect(res.resultEql(3.0));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer add with missing parameter, expect error" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1], "id": 1}
            , IntCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.InvalidParams));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of float add" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1.0, 2.0], "id": 1}
            , FloatCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.float, 3);
        try testing.expect(res.resultEql(3));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of float sub" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "sub", "params": [1, 2], "id": 1}
            , FloatCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.float, -1.0);
        try testing.expect(res.resultEql(-1));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of float multiply" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "multiply", "params": [10, 2], "id": 1}
            , FloatCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.float, 20);
        try testing.expect(res.resultEql(20));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of float divide" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "divide", "params": [10, 3], "id": 1}
            , FloatCalcDispatcher);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.float, 10.0/3.0);
        try testing.expect(res.resultEql(10.0/3.0));
        try testing.expect(res.id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response using an object based dispatcher." {
    const alloc = gpa.allocator();
    {
        var dispatcher = CounterDispatcher{};
        {
            var parsed_res = try zigjr.handleRequestToResponse(alloc,
                \\{"jsonrpc": "2.0", "method": "inc", "id": 1}
                , &dispatcher);
            defer parsed_res.deinit();
            try testing.expect(parsed_res.isNone());
        }
        {
            var parsed_res = try zigjr.handleRequestToResponse(alloc,
                \\{"jsonrpc": "2.0", "method": "inc", "id": 1}
                , &dispatcher);
            defer parsed_res.deinit();
            try testing.expect(parsed_res.isNone());
        }
        {
            var parsed_res = try zigjr.handleRequestToResponse(alloc,
                \\{"jsonrpc": "2.0", "method": "get", "id": 1}
                , &dispatcher);
            defer parsed_res.deinit();
            try testing.expect((try parsed_res.response()).resultEql(2));
        }
        {
            var parsed_res = try zigjr.handleRequestToResponse(alloc,
                \\{"jsonrpc": "2.0", "method": "dec", "id": 1}
                , &dispatcher);
            defer parsed_res.deinit();
            try testing.expect(parsed_res.isNone());
        }
        {
            var parsed_res = try zigjr.handleRequestToResponse(alloc,
                \\{"jsonrpc": "2.0", "method": "get", "id": 1}
                , &dispatcher);
            defer parsed_res.deinit();
            try testing.expect((try parsed_res.response()).resultEql(1));
        }
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer add with invalid parameter type, expect error" {
    const alloc = gpa.allocator();
    {
        var parsed_res = try zigjr.handleRequestToResponse(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": ["1", "2"], "id": 1}
            , FloatCalcDispatcher);
        defer parsed_res.deinit();
        try testing.expect((try parsed_res.response()).hasErr());
        try testing.expectEqual((try parsed_res.response()).err().code, @intFromEnum(ErrorCode.InvalidParams));
        try testing.expect((try parsed_res.response()).id.eql(1));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Construct a normal response message, simple integer result" {
    const alloc = gpa.allocator();
    {
        const response_json = try zigjr.messages.makeResponseJson(alloc, .{ .num = 1 }, "10");
        if (response_json)|res_json| {
            defer alloc.free(res_json);
            // std.debug.print("res_json: {s}\n", .{res_json});

            var parsed_res = try zigjr.parseRpcResponse(alloc, res_json);
            defer parsed_res.deinit();
            const res = try parsed_res.response();
            
            try testing.expect(!res.hasErr());
            try testing.expectEqual(res.result.integer, 10);
            try testing.expect(res.resultEql(10));
            try testing.expect(res.id.eql(1));
        }
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Construct a normal response message, array result" {
    const alloc = gpa.allocator();
    {
        const response_json = try zigjr.messages.makeResponseJson(alloc, zigjr.RpcId{ .str = "2" }, "[1, 2, 3]");
        if (response_json)|res_json| {
            defer alloc.free(res_json);
            // std.debug.print("res_json: {s}\n", .{res_json});

            var parsed_res = try zigjr.parseRpcResponse(alloc, res_json);
            defer parsed_res.deinit();
            const res = try parsed_res.response();

            try testing.expect(!res.hasErr());
            try testing.expectEqualSlices(Value, res.result.array.items, &[_]Value{ .{.integer = 1}, .{.integer = 2}, .{.integer=3} });
            try testing.expectEqualSlices(u8, res.id.str, "2");
        }
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Construct an error response message" {
    const alloc = gpa.allocator();
    {
        const res_json = try zigjr.messages.makeErrorResponseJson(alloc, .{ .none = {} },
                                                                  ErrorCode.InternalError, "Internal Error");
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseRpcResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.InternalError));
        try testing.expectEqualSlices(u8, res.err().message, "Internal Error");
        try testing.expect(res.id == .null);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Construct an error response message with data" {
    const alloc = gpa.allocator();
    {
        const res_json = try zigjr.messages.makeErrorDataResponseJson(alloc, .{ .none = {} },
                                                                      ErrorCode.InternalError, "Internal Error", "123");
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseRpcResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.InternalError));
        try testing.expectEqualSlices(u8, res.err().message, "Internal Error");
        try testing.expect(res.err().data != null);
        try testing.expectEqual(res.err().data.?.integer, 123);
        try testing.expect(res.id == .null);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "Handle batch requests with the CounterDispatcher" {
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
        const batch_req_json = try zigjr.messages.makeBatchRequestJson(alloc, &req_jsons);
        defer alloc.free(batch_req_json);
        // std.debug.print("batch request json {s}\n", .{batch_req_json});

        var batch_req_result = zigjr.parseRpcRequest(alloc, batch_req_json);
        defer batch_req_result.deinit();
        try testing.expect(batch_req_result.isBatch());
        try testing.expect((try batch_req_result.batch())[0].id.num == 1);
        try testing.expect((try batch_req_result.batch())[1].id.num == 2);

        var response_buf = std.ArrayList(u8).init(alloc);
        defer response_buf.deinit();
        _ = try zigjr.handleRpcRequests(alloc, try batch_req_result.batch(), &dispatcher, response_buf.writer());
        const batch_res_json = response_buf.items;
        // std.debug.print("batch response json {s}\n", .{batch_res_json});

        var batch_parsed_res = try zigjr.parseRpcResponse(alloc, batch_res_json);
        defer batch_parsed_res.deinit();
        const batch_res = try batch_parsed_res.batch();
        // for (batch_res)|res| std.debug.print("response {any}\n", .{res});

        try testing.expect(!batch_res[0].hasErr());
        try testing.expectEqual(batch_res[0].err().code, @intFromEnum(ErrorCode.None));
        try testing.expectEqualSlices(u8, batch_res[0].err().message, "");
        try testing.expect(batch_res[0].err().data == null);
        try testing.expect(batch_res[0].id.num == 2);
        try testing.expect(batch_res[0].result.integer == 1);
        try testing.expect(batch_res[0].resultEql(1));

        try testing.expect(batch_res[1].hasErr());
        try testing.expectEqual(batch_res[1].err().code, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expectEqualSlices(u8, batch_res[1].err().message, "MethodNotFound");
        try testing.expect(batch_res[1].err().data == null);
        try testing.expect(batch_res[1].id.num == 99);
        try testing.expect(batch_res[1].result == .null);
        try testing.expect(batch_res[1].resultEql(null));

        try testing.expect(!batch_res[2].hasErr());
        try testing.expectEqual(batch_res[2].err().code, @intFromEnum(ErrorCode.None));
        try testing.expectEqualSlices(u8, batch_res[2].err().message, "");
        try testing.expect(batch_res[2].err().data == null);
        try testing.expect(batch_res[2].id.num == 4);
        try testing.expect(batch_res[2].result.integer == 0);
        try testing.expect(batch_res[2].resultEql(0));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "handleRequestToJson on batch JSON requests with the CounterDispatcher" {
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
        const batch_req_json = try zigjr.messages.makeBatchRequestJson(alloc, &req_jsons);
        defer alloc.free(batch_req_json);
        // std.debug.print("batch request json {s}\n", .{batch_req_json});

        const batch_res_json = try zigjr.handleRequestToJson(alloc, batch_req_json, &dispatcher) orelse "";
        defer alloc.free(batch_res_json);

        var batch_parsed_res = try zigjr.parseRpcResponse(alloc, batch_res_json);
        defer batch_parsed_res.deinit();
        const batch_res = try batch_parsed_res.batch();
        // for (batch_res)|res| std.debug.print("response {any}\n", .{res});

        try testing.expect(!batch_res[0].hasErr());
        try testing.expectEqual(batch_res[0].err().code, @intFromEnum(ErrorCode.None));
        try testing.expectEqualSlices(u8, batch_res[0].err().message, "");
        try testing.expect(batch_res[0].err().data == null);
        try testing.expect(batch_res[0].id.num == 2);
        try testing.expect(batch_res[0].result.integer == 1);
        try testing.expect(batch_res[0].resultEql(1));

        try testing.expect(batch_res[1].hasErr());
        try testing.expectEqual(batch_res[1].err().code, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expectEqualSlices(u8, batch_res[1].err().message, "MethodNotFound");
        try testing.expect(batch_res[1].err().data == null);
        try testing.expect(batch_res[1].id.num == 99);
        try testing.expect(batch_res[1].result == .null);
        try testing.expect(batch_res[1].resultEql(null));

        try testing.expect(!batch_res[2].hasErr());
        try testing.expectEqual(batch_res[2].err().code, @intFromEnum(ErrorCode.None));
        try testing.expectEqualSlices(u8, batch_res[2].err().message, "");
        try testing.expect(batch_res[2].err().data == null);
        try testing.expect(batch_res[2].id.num == 4);
        try testing.expect(batch_res[2].result.integer == 0);
        try testing.expect(batch_res[2].resultEql(0));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "Handle empty batch response" {
    const alloc = gpa.allocator();
    {
        var dispatcher = CounterDispatcher{};
        const req_jsons = [_][]const u8{};
        const batch_req_json = try zigjr.messages.makeBatchRequestJson(alloc, &req_jsons);
        defer alloc.free(batch_req_json);
        // std.debug.print("batch request json {s}\n", .{batch_req_json});

        var batch_req_result = zigjr.parseRpcRequest(alloc, batch_req_json);
        defer batch_req_result.deinit();
        try testing.expect(batch_req_result.isBatch());
        try testing.expect((try batch_req_result.batch()).len == 0);

        var batch_res_buf = std.ArrayList(u8).init(alloc);
        defer batch_res_buf.deinit();
        try zigjr.handleRpcRequests(alloc, try batch_req_result.batch(), &dispatcher, batch_res_buf.writer());
        const batch_res_json = batch_res_buf.items;
        // std.debug.print("batch response json {s}\n", .{batch_res_json});

        var batch_parsed_res = try zigjr.parseRpcResponse(alloc, batch_res_json);
        defer batch_parsed_res.deinit();
        const batch_res = try batch_parsed_res.batch();
        for (batch_res)|res| std.debug.print("response {any}\n", .{res});

        try testing.expect(batch_res.len == 0);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatch on the response to a request of float add" {
    const alloc = gpa.allocator();
    {
        var response_buf = std.ArrayList(u8).init(alloc);
        defer response_buf.deinit();
        _ = try zigjr.handleJsonRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1.0, 2.0], "id": 1}
            , response_buf.writer(), FloatCalcDispatcher);
        const res_json = response_buf.items;
        // std.debug.print("res_json: {s}\n", .{res_json});

        try zigjr.handleJsonResponse(alloc, res_json, struct {
            pub fn dispatch(_: Allocator, res: zigjr.RpcResponse) !void {
                // std.debug.print("response: {any}\n", .{res});
                try testing.expectEqual(res.result.float, 3);
                try testing.expect(res.resultEql(3));
                try testing.expect(res.resultEql(3.0));
                try testing.expect(res.id.eql(1));
            }
        });
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatch batch responses on batch JSON requests with the CounterDispatcher" {
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
            \\{"jsonrpc": "2.0", "method": "no-method", "id": "abc"}
            ,
            \\{"jsonrpc": "2.0", "method": "get", "id": 4}
            ,
        };
        const batch_req_json = try zigjr.messages.makeBatchRequestJson(alloc, &req_jsons);
        defer alloc.free(batch_req_json);
        // std.debug.print("batch request json {s}\n", .{batch_req_json});

        const batch_res_json = try zigjr.handleRequestToJson(alloc, batch_req_json, &dispatcher) orelse "";
        defer alloc.free(batch_res_json);

        const non_exist_id = "xyz";

        try zigjr.handleJsonResponse(alloc, batch_res_json, struct {
            pub fn dispatch(_: Allocator, res: zigjr.RpcResponse) !void {
                // std.debug.print("response: {any}\n", .{res});
                if (res.id.eql(2)) {
                    try testing.expectEqual(res.result.integer, 1);
                } else if (res.id.eql("abc")) {
                    try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.MethodNotFound));
                } else if (res.id.eql(non_exist_id)) {
                    std.debug.print("response: {any}\n", .{res});
                } else if (res.id.eql(4)) {
                    try testing.expectEqual(res.result.integer, 0);
                }
            }
        });
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



