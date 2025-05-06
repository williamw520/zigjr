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
    pub fn run(_: Allocator, req: RpcRequest) !DispatchResult {
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

    pub fn free(_: Allocator, dresult: DispatchResult) void {
        // All result data are constant strings.  Nothing to free.
        switch (dresult) {
            .result => {},
            .err => {},
            .none => {},
        }
    }
};

const IntCalcDispatcher = struct {
    pub fn run(alloc: Allocator, req: RpcRequest) !DispatchResult {
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

    pub fn free(alloc: Allocator, dresult: DispatchResult) void {
        switch (dresult) {
            .result => alloc.free(dresult.result),
            .err => {},
            .none => {},
        }
    }
    
    fn add(a: i64, b: i64) i64 { return a + b; }
    fn sub(a: i64, b: i64) i64 { return a - b; }
    fn multiply(a: i64, b: i64) i64 { return a * b; }
    fn divide(a: i64, b: i64) i64 { return @divTrunc(a, b); }
};

const FloatCalcDispatcher = struct {
    pub fn run(alloc: Allocator, req: RpcRequest) !DispatchResult {
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

    pub fn free(alloc: Allocator, dresult: DispatchResult) void {
        switch (dresult) {
            .result => alloc.free(dresult.result),
            .err => {},
            else => {},
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
            return .{ .result = try stringifyAlloc(alloc, self.count, .{}) };
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


test "Response to a request of hello method" {
    const alloc = gpa.allocator();
    {
        var req_result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
        );
        defer req_result.deinit();

        const response = try zigjr.runRequest(alloc, try req_result.request(), HelloDispatcher);
        const res_json = response orelse "";
        defer alloc.free(res_json);
        // std.debug.print("response: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();
        // std.debug.print("res.result: {s}\n", .{res.result.string});

        try testing.expectEqualSlices(u8, res.result.string, "hello back");
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "runRequestJson on a request of hello method" {
    const alloc = gpa.allocator();
    {
        const response = try zigjr.runRequestJson(alloc,
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
        , HelloDispatcher);
        const res_json = response orelse "";
        defer alloc.free(res_json);
        // std.debug.print("response: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();
        // std.debug.print("res.result: {s}\n", .{res.result.string});

        try testing.expectEqualSlices(u8, res.result.string, "hello back");
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "runRequestJson on a request of unknown method, expect error" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "non-hello", "params": [42], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), HelloDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "runRequestJson to a request with anonymous dispatcher struct" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
        );
        defer result.deinit();

        const response = try zigjr.runRequest(alloc, try result.request(), struct {
            pub fn run(_: Allocator, _: RpcRequest) !DispatchResult {
                return .{ .result = "\"hello back\"" };
            }
            pub fn free(_: Allocator, dresult: DispatchResult) void {
                switch (dresult) {
                    else => {}
                }
            }
        });
        const res_json = response orelse "";
        defer alloc.free(res_json);
        // std.debug.print("response: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        // std.debug.print("res.result: {}\n", .{try parsed_res.response()});

        try testing.expectEqualSlices(u8, (try parsed_res.response()).result.string, "hello back");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer add" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1, 2], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, 3);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "runRequestJson on a request of integer add" {
    const alloc = gpa.allocator();
    {
        const res_json = try zigjr.runRequestJson(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1, 2], "id": 1}
        , IntCalcDispatcher) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, 3);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer sub" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "sub", "params": [1, 2], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, -1);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer multiply" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "multiply", "params": [10, 2], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, 20);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer divide" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "divide", "params": [10, 3], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.integer, 3);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer add with missing parameter, expect error" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.InvalidParams));
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of float add" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1.0, 2.0], "id": 1}
        );
        defer result.deinit();
        const res_json = (try zigjr.runRequest(alloc, try result.request(), FloatCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.float, 3);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of float sub" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "sub", "params": [1, 2], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), FloatCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.float, -1.0);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of float multiply" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "multiply", "params": [10, 2], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), FloatCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.float, 20);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of float divide" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "divide", "params": [10, 3], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), FloatCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expectEqual(res.result.float, 10.0/3.0);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response using an object based dispatcher." {
    const alloc = gpa.allocator();
    {
        var dispatcher = CounterDispatcher{};
        {
            var result = zigjr.parseRequest(alloc,
                \\{"jsonrpc": "2.0", "method": "inc", "id": 1}
            );
            defer result.deinit();

            const res = try zigjr.runRequest(alloc, try result.request(), &dispatcher);
            // std.debug.print("res_json: {any}\n", .{res});
            try testing.expectEqual(res, null);
        }
        {
            var result = zigjr.parseRequest(alloc,
                \\{"jsonrpc": "2.0", "method": "inc", "id": 1}
            );
            defer result.deinit();

            const res = try zigjr.runRequest(alloc, try result.request(), &dispatcher);
            try testing.expectEqual(res, null);
        }
        {
            var result = zigjr.parseRequest(alloc,
                \\{"jsonrpc": "2.0", "method": "get", "id": 1}
            );
            defer result.deinit();

            const res_json = (try zigjr.runRequest(alloc, try result.request(), &dispatcher)) orelse "";
            defer alloc.free(res_json);

            var parsed_res = try zigjr.parseResponse(alloc, res_json);
            defer parsed_res.deinit();
            const res = try parsed_res.response();
            try testing.expectEqual(res.result.integer, 2);
        }
        {
            var result = zigjr.parseRequest(alloc,
                \\{"jsonrpc": "2.0", "method": "dec", "id": 1}
            );
            defer result.deinit();

            const res = try zigjr.runRequest(alloc, try result.request(), &dispatcher);
            try testing.expectEqual(res, null);
        }
        {
            var result = zigjr.parseRequest(alloc,
                \\{"jsonrpc": "2.0", "method": "get", "id": 1}
            );
            defer result.deinit();

            const res_json = (try zigjr.runRequest(alloc, try result.request(), &dispatcher)) orelse "";
            defer alloc.free(res_json);

            var parsed_res = try zigjr.parseResponse(alloc, res_json);
            defer parsed_res.deinit();
            const res = try parsed_res.response();
            try testing.expectEqual(res.result.integer, 1);
        }
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Response to a request of integer add with invalid parameter type, expect error" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": ["1", "2"], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.runRequest(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err().code, @intFromEnum(ErrorCode.InvalidParams));
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Construct a normal response message, simple integer result" {
    const alloc = gpa.allocator();
    {
        const res_json = try zigjr.messages.responseJson(alloc, .{ .num = 1 }, "10");
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();
 
        try testing.expect(!res.hasErr());
        try testing.expectEqual(res.result.integer, 10);
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Construct a normal response message, array result" {
    const alloc = gpa.allocator();
    {
        const res_json = try zigjr.messages.responseJson(alloc, .{ .str = "2" }, "[1, 2, 3]");
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
        defer parsed_res.deinit();
        const res = try parsed_res.response();

        try testing.expect(!res.hasErr());
        try testing.expectEqualSlices(Value, res.result.array.items, &[_]Value{ .{.integer = 1}, .{.integer = 2}, .{.integer=3} });
        try testing.expectEqualSlices(u8, res.id.str, "2");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Construct an error response message" {
    const alloc = gpa.allocator();
    {
        const res_json = try zigjr.messages.responseErrorJson(alloc, .{ .none = {} }, ErrorCode.InternalError, "Internal Error");
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
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
        const res_json = try zigjr.messages.responseErrorDataJson(alloc, .{ .none = {} }, ErrorCode.InternalError, "Internal Error", "123");
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var parsed_res = try zigjr.parseResponse(alloc, res_json);
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
        const batch_req_json = try zigjr.messages.batchJson(alloc, &req_jsons);
        defer alloc.free(batch_req_json);
        // std.debug.print("batch request json {s}\n", .{batch_req_json});

        var batch_req_result = zigjr.parseRequest(alloc, batch_req_json);
        defer batch_req_result.deinit();
        try testing.expect(batch_req_result.isBatch());
        try testing.expect((try batch_req_result.batch())[0].id.num == 1);
        try testing.expect((try batch_req_result.batch())[1].id.num == 2);

        const batch_res_json = try zigjr.runRequestBatch(alloc, try batch_req_result.batch(), &dispatcher);
        defer alloc.free(batch_res_json);
        // std.debug.print("batch response json {s}\n", .{batch_res_json});

        var batch_parsed_res = try zigjr.parseResponse(alloc, batch_res_json);
        defer batch_parsed_res.deinit();
        const batch_res = try batch_parsed_res.batch();
        // for (batch_res)|res| std.debug.print("response {any}\n", .{res});

        try testing.expect(!batch_res[0].hasErr());
        try testing.expectEqual(batch_res[0].err().code, @intFromEnum(ErrorCode.None));
        try testing.expectEqualSlices(u8, batch_res[0].err().message, "");
        try testing.expect(batch_res[0].err().data == null);
        try testing.expect(batch_res[0].id.num == 2);
        try testing.expect(batch_res[0].result.integer == 1);

        try testing.expect(batch_res[1].hasErr());
        try testing.expectEqual(batch_res[1].err().code, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expectEqualSlices(u8, batch_res[1].err().message, "MethodNotFound");
        try testing.expect(batch_res[1].err().data == null);
        try testing.expect(batch_res[1].id.num == 99);
        try testing.expect(batch_res[1].result == .null);

        try testing.expect(!batch_res[2].hasErr());
        try testing.expectEqual(batch_res[2].err().code, @intFromEnum(ErrorCode.None));
        try testing.expectEqualSlices(u8, batch_res[2].err().message, "");
        try testing.expect(batch_res[2].err().data == null);
        try testing.expect(batch_res[2].id.num == 4);
        try testing.expect(batch_res[2].result.integer == 0);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "runRequestJson on batch JSON requests with the CounterDispatcher" {
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
        const batch_req_json = try zigjr.messages.batchJson(alloc, &req_jsons);
        defer alloc.free(batch_req_json);
        // std.debug.print("batch request json {s}\n", .{batch_req_json});

        const batch_res_json = try zigjr.runRequestJson(alloc, batch_req_json, &dispatcher) orelse "";
        defer alloc.free(batch_res_json);

        var batch_parsed_res = try zigjr.parseResponse(alloc, batch_res_json);
        defer batch_parsed_res.deinit();
        const batch_res = try batch_parsed_res.batch();
        // for (batch_res)|res| std.debug.print("response {any}\n", .{res});

        try testing.expect(!batch_res[0].hasErr());
        try testing.expectEqual(batch_res[0].err().code, @intFromEnum(ErrorCode.None));
        try testing.expectEqualSlices(u8, batch_res[0].err().message, "");
        try testing.expect(batch_res[0].err().data == null);
        try testing.expect(batch_res[0].id.num == 2);
        try testing.expect(batch_res[0].result.integer == 1);

        try testing.expect(batch_res[1].hasErr());
        try testing.expectEqual(batch_res[1].err().code, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expectEqualSlices(u8, batch_res[1].err().message, "MethodNotFound");
        try testing.expect(batch_res[1].err().data == null);
        try testing.expect(batch_res[1].id.num == 99);
        try testing.expect(batch_res[1].result == .null);

        try testing.expect(!batch_res[2].hasErr());
        try testing.expectEqual(batch_res[2].err().code, @intFromEnum(ErrorCode.None));
        try testing.expectEqualSlices(u8, batch_res[2].err().message, "");
        try testing.expect(batch_res[2].err().data == null);
        try testing.expect(batch_res[2].id.num == 4);
        try testing.expect(batch_res[2].result.integer == 0);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "Handle empty batch response" {
    const alloc = gpa.allocator();
    {
        var dispatcher = CounterDispatcher{};
        const req_jsons = [_][]const u8{};
        const batch_req_json = try zigjr.messages.batchJson(alloc, &req_jsons);
        defer alloc.free(batch_req_json);
        // std.debug.print("batch request json {s}\n", .{batch_req_json});

        var batch_req_result = zigjr.parseRequest(alloc, batch_req_json);
        defer batch_req_result.deinit();
        try testing.expect(batch_req_result.isBatch());
        try testing.expect((try batch_req_result.batch()).len == 0);

        const batch_res_json = try zigjr.runRequestBatch(alloc, try batch_req_result.batch(), &dispatcher);
        defer alloc.free(batch_res_json);
        // std.debug.print("batch response json {s}\n", .{batch_res_json});

        var batch_parsed_res = try zigjr.parseResponse(alloc, batch_res_json);
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
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1.0, 2.0], "id": 1}
        );
        defer result.deinit();
        const res_json = (try zigjr.runRequest(alloc, try result.request(), FloatCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        try zigjr.runResponseJson(alloc, res_json, struct {
            pub fn run(_: Allocator, res: zigjr.RpcResponse) !void {
                // std.debug.print("response: {any}\n", .{res});
                try testing.expectEqual(res.result.float, 3);
                try testing.expectEqual(res.id.num, 1);
            }
        });
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}




