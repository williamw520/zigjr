const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;
const stringifyAlloc = std.json.stringifyAlloc;

const zigjr = @import("../zigjr.zig");
const RpcMessage = zigjr.RpcMessage;
const RpcRequest = zigjr.RpcRequest;
const DispatchResult = zigjr.DispatchResult;
const ErrorCode = zigjr.ErrorCode;
const JrErrors = zigjr.JrErrors;
const DispatchErrors = zigjr.DispatchErrors;


var gpa = std.heap.GeneralPurposeAllocator(.{}){};


const HelloDispatcher = struct {
    pub fn run(alloc: Allocator, req: RpcRequest) !DispatchResult {
        if (std.mem.eql(u8, req.method, "hello")) {
            return .{ .result = try stringifyAlloc(alloc, "hello back", .{}) };
        } else {
            return .{
                .err = .{
                    .code = ErrorCode.MethodNotFound,
                    .msg = "Method not found.",
                }
            };
        }
    }
};

const IntCalcDispatcher = struct {
    pub fn run(alloc: Allocator, req: RpcRequest) !DispatchResult {
        const params = try req.arrayParams();
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
        return .{ .result = try stringifyAlloc(alloc, result, .{}) };
    }

    fn add(a: i64, b: i64) i64 { return a + b; }
    fn sub(a: i64, b: i64) i64 { return a - b; }
    fn multiply(a: i64, b: i64) i64 { return a * b; }
    fn divide(a: i64, b: i64) i64 { return @divTrunc(a, b); }
};

const CounterDispatcher = struct {
    count:  isize = 0,
    
    pub fn run(self: *@This(), alloc: Allocator, _: RpcRequest) !DispatchResult {
        self.count += 1;
        return .{ .result = try stringifyAlloc(alloc, self.count, .{}) };
    }
};


test "Response to a request of hello method" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
        );
        defer result.deinit();

        const response = try zigjr.respond(alloc, try result.request(), HelloDispatcher);
        const res_json = response orelse "";
        defer alloc.free(res_json);
        // std.debug.print("response: {s}\n", .{res_json});

        var res = try zigjr.parseResponse(alloc, res_json);
        defer res.deinit();
        // std.debug.print("resResult: {any}\n", .{res.result});

        try testing.expectEqualSlices(u8, res.result.string, "hello back");
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Response to a request of unknown method, expect error" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "non-hello", "params": [42], "id": 1}
        );
        defer result.deinit();

        const res_json = (try zigjr.respond(alloc, try result.request(), HelloDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var res = try zigjr.parseResponse(alloc, res_json);
        defer res.deinit();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err.code, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expectEqual(res.id.num, 1);
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
        const res_json = (try zigjr.respond(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var res = try zigjr.parseResponse(alloc, res_json);
        defer res.deinit();

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

        const res_json = (try zigjr.respond(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var res = try zigjr.parseResponse(alloc, res_json);
        defer res.deinit();

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

        const res_json = (try zigjr.respond(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var res = try zigjr.parseResponse(alloc, res_json);
        defer res.deinit();

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

        const res_json = (try zigjr.respond(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var res = try zigjr.parseResponse(alloc, res_json);
        defer res.deinit();

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

        const res_json = (try zigjr.respond(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);
        // std.debug.print("res_json: {s}\n", .{res_json});

        var res = try zigjr.parseResponse(alloc, res_json);
        defer res.deinit();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err.code, @intFromEnum(ErrorCode.InvalidParams));
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Response using an object based dispatcher." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseRequest(alloc,
            \\{"jsonrpc": "2.0", "method": "foobar", "id": 1}
        );
        defer result.deinit();

        var dispatcher = CounterDispatcher{};
        {
            const res_json = (try zigjr.respond(alloc, try result.request(), &dispatcher)) orelse "";
            defer alloc.free(res_json);
            // std.debug.print("res_json: {s}\n", .{res_json});
            var res = try zigjr.parseResponse(alloc, res_json);
            defer res.deinit();
            try testing.expectEqual(res.result.integer, 1);
        }
        {
            const res_json = (try zigjr.respond(alloc, try result.request(), &dispatcher)) orelse "";
            defer alloc.free(res_json);
            var res = try zigjr.parseResponse(alloc, res_json);
            defer res.deinit();
            try testing.expectEqual(res.result.integer, 2);
        }
        {
            const res_json = (try zigjr.respond(alloc, try result.request(), &dispatcher)) orelse "";
            defer alloc.free(res_json);
            var res = try zigjr.parseResponse(alloc, res_json);
            defer res.deinit();
            try testing.expectEqual(res.result.integer, 3);
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

        const res_json = (try zigjr.respond(alloc, try result.request(), IntCalcDispatcher)) orelse "";
        defer alloc.free(res_json);

        var res = try zigjr.parseResponse(alloc, res_json);
        defer res.deinit();

        try testing.expect(res.hasErr());
        try testing.expectEqual(res.err.code, @intFromEnum(ErrorCode.InvalidParams));
        try testing.expectEqual(res.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    



