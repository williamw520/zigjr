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
const RpcMessage = zigjr.RpcMessage;
const RpcRequest = zigjr.RpcRequest;
const ErrorCode = zigjr.ErrorCode;
const JrErrors = zigjr.JrErrors;
const DispatchErrors = zigjr.DispatchErrors;


var gpa = std.heap.GeneralPurposeAllocator(.{}){};


const HelloDispatcher = struct {
    pub fn run(alloc: Allocator, req: RpcRequest) anyerror![]const u8 {
        if (std.mem.eql(u8, req.method, "hello")) {
            return std.json.stringifyAlloc(alloc, "hello back", .{});
        } else {
            return DispatchErrors.MethodNotFound;
        }
    }

    pub fn getErrorCodeMsg(err: anyerror) struct {ErrorCode, []const u8} {
        return switch (err) {
            DispatchErrors.MethodNotFound => .{ ErrorCode.MethodNotFound, "Method not found." },
            else => .{ ErrorCode.InternalError, @errorName(err) }
        };
    }
};

const IntCalcDispatcher = struct {
    pub fn run(alloc: Allocator, req: RpcRequest) anyerror![]const u8 {
        const params = try req.arrayParams();
        const a = params.items[0].integer;
        const b = params.items[1].integer;
        if (std.mem.eql(u8, req.method, "add")) {
            return std.json.stringifyAlloc(alloc, add(a, b), .{});
        } else if (std.mem.eql(u8, req.method, "sub")) {
            return std.json.stringifyAlloc(alloc, sub(a, b), .{});
        } else if (std.mem.eql(u8, req.method, "multiply")) {
            return std.json.stringifyAlloc(alloc, multiply(a, b), .{});
        } else if (std.mem.eql(u8, req.method, "divide")) {
            return std.json.stringifyAlloc(alloc, divide(a, b), .{});
        } else {
            return DispatchErrors.MethodNotFound;
        }
    }

    pub fn getErrorCodeMsg(err: anyerror) struct {ErrorCode, []const u8} {
        return switch (err) {
            DispatchErrors.MethodNotFound => .{ ErrorCode.MethodNotFound, "Method not found." },
            else => .{ ErrorCode.InternalError, @errorName(err) }
        };
    }

    fn add(a: i64, b: i64) i64 { return a + b; }
    fn sub(a: i64, b: i64) i64 { return a - b; }
    fn multiply(a: i64, b: i64) i64 { return a * b; }
    fn divide(a: i64, b: i64) i64 { return @divTrunc(a, b); }
};


test "Response to a request of hello method" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "hello", "params": [42], "id": 1}
        );
        defer result.deinit();
        const response = try zigjr.response(alloc, try result.request(), HelloDispatcher);
        defer alloc.free(response);
        // std.debug.print("response: {s}\n", .{response});

        var res = try zigjr.parseResponse(alloc, response);
        res.deinit();
        // std.debug.print("resResult: {any}\n", .{(try res.result())});
        try testing.expectEqualSlices(u8, (try res.result()).string, "hello back");
        try testing.expectEqual(res.body.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Response to a request of unknown method, expect error" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "non-hello", "params": [42], "id": 1}
        );
        defer result.deinit();
        const response = try zigjr.response(alloc, try result.request(), HelloDispatcher);
        defer alloc.free(response);
        // std.debug.print("response: {s}\n", .{response});

        var res = try zigjr.parseResponse(alloc, response);
        res.deinit();
        // std.debug.print("resResult: {any}\n", .{(try resResult.err())});
        try testing.expectEqual((try res.err()).code, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expectEqual(res.body.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Response to a request of integer add" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "add", "params": [1, 2], "id": 1}
        );
        defer result.deinit();
        const response = try zigjr.response(alloc, try result.request(), IntCalcDispatcher);
        defer alloc.free(response);
        // std.debug.print("response: {s}\n", .{response});

        var res = try zigjr.parseResponse(alloc, response);
        res.deinit();
        try testing.expectEqual((try res.result()).integer, 3);
        try testing.expectEqual(res.body.id.num, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    




// Pending...

test "Parsing valid request, single string param, string id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": "1"}
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun1"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 1);
        try testing.expect(std.mem.eql(u8, req.params.array.items[0].string, "FUN1"));
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != JrErrors.NotArray);
        try testing.expect(req.objectParams() == JrErrors.NotObject);
        try testing.expect((try req.arrayParams()).items.len == 1);
        try testing.expect(std.mem.eql(u8, (try req.arrayParams()).items[0].string, "FUN1"));
        try testing.expect(req.hasValidId());
        try testing.expect(std.mem.eql(u8, req.id.str, "1"));
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Parsing valid request, tw0 integer params, integer id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun1", "params": [42, 22], "id": 2}
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun1"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 2);
        try testing.expect(req.params.array.items[0].integer == 42);
        try testing.expect(req.params.array.items[1].integer == 22);
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != JrErrors.NotArray);
        try testing.expect(req.objectParams() == JrErrors.NotObject);
        try testing.expect((try req.arrayParams()).items.len == 2);
        try testing.expect((try req.arrayParams()).items[0].integer == 42);
        try testing.expect((try req.arrayParams()).items[1].integer == 22);
        try testing.expect(req.hasValidId());
        try testing.expect(req.id.num == 2);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Parsing valid request, object params, integer id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun_obj", "params": { "name": "foobar", "weight": 150 }, "id": 3}
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun_obj"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .object);
        try testing.expect(std.mem.eql(u8, req.params.object.get("name").?.string, "foobar"));
        try testing.expect(req.params.object.get("weight").?.integer == 150);
        try testing.expect(!req.hasArrayParams());
        try testing.expect(req.hasObjectParams());
        try testing.expect(req.arrayParams()  == JrErrors.NotArray);
        try testing.expect(req.objectParams() != JrErrors.NotObject);
        try testing.expect(std.mem.eql(u8, (try req.objectParams()).get("name").?.string, "foobar"));
        try testing.expect((try req.objectParams()).get("weight").?.integer == 150);
        try testing.expect(req.hasValidId());
        try testing.expect(req.id.num == 3);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Parse valid request, with 0 params, with no id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0", "params": [] }
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun0"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 0);
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != JrErrors.NotArray);
        try testing.expect(req.objectParams() == JrErrors.NotObject);
        try testing.expect((try req.arrayParams()).items.len == 0);
        try testing.expect(!req.hasValidId());
        try testing.expect(req.id == zigjr.RpcId.none);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request, with no params, with no id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0" }
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun0"));
        try testing.expect(!req.hasParams());
        try testing.expect(req.params == .null);
        try testing.expect(!req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  == JrErrors.NotArray);
        try testing.expect(req.objectParams() == JrErrors.NotObject);
        try testing.expect(!req.hasValidId());
        try testing.expect(req.id == zigjr.RpcId.none);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request, with no params, with string id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5a" }
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(req.hasValidId());
        try testing.expect(std.mem.eql(u8, req.id.str, "5a"));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request batch, with no params, with string id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\[ {"jsonrpc": "2.0", "method": "fun0", "id": "5a" },
            \\  {"jsonrpc": "2.0", "method": "fun0", "id": "5b" } ]
        );
        defer result.deinit();
        try testing.expect(result.isBatch());
        try testing.expect(!result.isRequest());
        const reqs = try result.batch();
        try testing.expect(reqs.len == 2);
        try testing.expect(reqs[0].hasValidId());
        try testing.expect(reqs[1].hasValidId());
        try testing.expect(std.mem.eql(u8, reqs[0].id.str, "5a"));
        try testing.expect(std.mem.eql(u8, reqs[1].id.str, "5b"));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



// Testing parsing errors and invalid requests.

test "Parse empty request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(req.hasError());
        try testing.expect(req.err.code == ErrorCode.InvalidRequest);
        try testing.expect(req.isError(ErrorCode.InvalidRequest));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse incomplete opening request {, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(req.hasError());
        try testing.expect(req.err.code == ErrorCode.InvalidRequest);
        try testing.expect(req.isError(ErrorCode.InvalidRequest));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse incomplete closing request }, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\}
        );
        defer result.deinit();
        // std.debug.print("Error {}, {s}\n", .{(try result.request()).err.code, (try result.request()).err.err_msg});
        try testing.expect((try result.request()).err.code == ErrorCode.ParseError);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse empty object request {}, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{}
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse invalid syntax request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\ foo abc 123
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.ParseError);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse incomplete missing value request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"foo":
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse missing value request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"foo": }
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse missing value for 'jsonrpc' property, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": }
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.ParseError);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse incomplete jsonrpc request 'jsonrpc' only, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0"}
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse duplicate 'params' properties, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "methodx": "foobar", "params": [], "id": "4"}
        );
        defer result.deinit();
        // try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse invalid jsonrpc version 0.0, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "0.0", "method": "foobar", "params": [], "id": "5"}
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse invalid jsonrpc version 1.0, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "1.0", "method": "foobar", "params": [], "id": "5"}
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse invalid jsonrpc version 3.0, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "3.0", "method": "foobar", "params": [], "id": "5"}
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse empty method, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": ""}
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse non-object nor non-array params '1234', expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "foobar", "params": 1234, "id": "5d"}
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidParams);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse non-object nor non-array params 'abcd', expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "foobar", "params": "abcd", "id": "5d"}
        );
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidParams);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

// Test parseReader

test "Parsing valid request with parseReader, single integer param, integer id" {
    const alloc = gpa.allocator();
    {
        var json_stream = std.io.fixedBufferStream(
            \\{"jsonrpc": "2.0", "method": "fun0", "params": [42], "id": 1}
        );
        const json_reader = json_stream.reader();
        var result = zigjr.parseReader(alloc, json_reader);
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun0"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 1);
        try testing.expect(req.params.array.items[0].integer == 42);
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != JrErrors.NotArray);
        try testing.expect(req.objectParams() == JrErrors.NotObject);
        try testing.expect((try req.arrayParams()).items.len == 1);
        try testing.expect((try req.arrayParams()).items[0].integer == 42);
        try testing.expect(req.hasValidId());
        try testing.expect(req.id.num == 1);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Parsing valid request with parseReader, single string param, string id" {
    const alloc = gpa.allocator();
    {
        var json_stream = std.io.fixedBufferStream(
            \\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": "1"}
        );
        const json_reader = json_stream.reader();
        var result = zigjr.parseReader(alloc, json_reader);
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpcmsg) == RpcMessage);
        try testing.expect(result.rpcmsg == .request);
        switch (result.rpcmsg) {
            .request    => |r| { _=r; try testing.expect(true);  },
            .batch      => |b| { _=b; try testing.expect(false); },
        }
        try testing.expect(result.isRequest());
        try testing.expect(!result.isBatch());
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        try testing.expect(std.mem.eql(u8, &req.jsonrpc, "2.0"));
        try testing.expect(std.mem.eql(u8, req.method, "fun1"));
        try testing.expect(req.hasParams());
        try testing.expect(req.params == .array);
        try testing.expect(req.params.array.items.len == 1);
        try testing.expect(std.mem.eql(u8, req.params.array.items[0].string, "FUN1"));
        try testing.expect(req.hasArrayParams());
        try testing.expect(!req.hasObjectParams());
        try testing.expect(req.arrayParams()  != JrErrors.NotArray);
        try testing.expect(req.objectParams() == JrErrors.NotObject);
        try testing.expect((try req.arrayParams()).items.len == 1);
        try testing.expect(std.mem.eql(u8, (try req.arrayParams()).items[0].string, "FUN1"));
        try testing.expect(req.hasValidId());
        try testing.expect(std.mem.eql(u8, req.id.str, "1"));
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Parse missing value request with parseReader, expect error." {
    const alloc = gpa.allocator();
    {
        var json_stream = std.io.fixedBufferStream(
            \\{"foo": }
        );
        const json_reader = json_stream.reader();
        var result = zigjr.parseReader(alloc, json_reader);
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse empty method with parseJson, expect error." {
    const alloc = gpa.allocator();
    {
        var json_stream = std.io.fixedBufferStream(
            \\{"jsonrpc": "2.0", "method": ""}
        );
        const json_reader = json_stream.reader();
        var result = zigjr.parseReader(alloc, json_reader);
        defer result.deinit();
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request and get as a batch, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5a" }
        );
        try testing.expect(!result.isBatch());
        try testing.expect(result.isRequest());
        defer result.deinit();
        try testing.expect(result.batch() == JrErrors.NotBatchRpcRequest);
        
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse valid request batch and get as a request, expect error." {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\[ {"jsonrpc": "2.0", "method": "fun0", "id": "5a" },
            \\  {"jsonrpc": "2.0", "method": "fun0", "id": "5b" } ]
        );
        try testing.expect(result.isBatch());
        try testing.expect(!result.isRequest());
        try testing.expect(result.isBatch());
        defer result.deinit();
        try testing.expect(result.request() == JrErrors.NotSingleRpcRequest);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



