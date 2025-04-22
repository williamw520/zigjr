const std = @import("std");
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const zigjr = @import("zigjr.zig");
const RpcMessage = zigjr.RpcMessage;
const RpcRequest = zigjr.RpcRequest;
const ErrorCode = zigjr.ErrorCode;
const JrErrors = zigjr.JrErrors;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};


fn foo(p1: u32) !usize { return p1 + 2; }

test "check out type info detail" {
    const type_foo = @TypeOf(foo);
    const info_foo = @typeInfo(type_foo);
    const info_fn_foo = info_foo.@"fn";
    const return_type = info_fn_foo.return_type;
    const params = info_fn_foo.params;
    const param_count = params.len;

    // std.debug.print("TypeOf: {any}\n", .{type_foo});
    // std.debug.print("typeInfo: {any}\n", .{info_foo});
    // std.debug.print("info_fn: {any}\n", .{info_fn_foo});
    // std.debug.print("return_type: {any}\n", .{return_type});
    // std.debug.print("param_count: {any}\n", .{param_count});
    // std.debug.print("params[0]: {any}\n", .{params[0]});

    if (return_type) |typ| {
        _=typ;
        // std.debug.print(" return_typ: {any}\n", .{typ});
    }
    try testing.expect(param_count == 1);
    try testing.expect(params[0].type == u32);
}

test "Parsing valid request, single integer param, integer id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0", "params": [42], "id": 1}
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpc_msg) == RpcMessage);
        try testing.expect(result.rpc_msg == .request);
        switch (result.rpc_msg) {
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
        try testing.expect(req.hasId());
        try testing.expect(req.id.num == 1);
        try testing.expect(req.hasError() == false);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}    

test "Parsing valid request, single string param, string id" {
    const alloc = gpa.allocator();
    {
        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": "1"}
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(@TypeOf(result.rpc_msg) == RpcMessage);
        try testing.expect(result.rpc_msg == .request);
        switch (result.rpc_msg) {
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
        try testing.expect(req.hasId());
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
        try testing.expect(@TypeOf(result.rpc_msg) == RpcMessage);
        try testing.expect(result.rpc_msg == .request);
        switch (result.rpc_msg) {
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
        try testing.expect(req.hasId());
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
        try testing.expect(@TypeOf(result.rpc_msg) == RpcMessage);
        try testing.expect(result.rpc_msg == .request);
        switch (result.rpc_msg) {
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
        try testing.expect(req.hasId());
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
        try testing.expect(@TypeOf(result.rpc_msg) == RpcMessage);
        try testing.expect(result.rpc_msg == .request);
        switch (result.rpc_msg) {
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
        try testing.expect(!req.hasId());
        try testing.expect(req.id == zigjr.RpcId.null);
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
        try testing.expect(@TypeOf(result.rpc_msg) == RpcMessage);
        try testing.expect(result.rpc_msg == .request);
        switch (result.rpc_msg) {
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
        try testing.expect(!req.hasId());
        try testing.expect(req.id == zigjr.RpcId.null);
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
        try testing.expect(req.hasId());
        try testing.expect(std.mem.eql(u8, req.id.str, "5a"));
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
        try testing.expect((try result.request()).err.code == ErrorCode.ParseError);
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
        try testing.expect((try result.request()).err.code == ErrorCode.InvalidRequest);
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
        try testing.expect(@TypeOf(result.rpc_msg) == RpcMessage);
        try testing.expect(result.rpc_msg == .request);
        switch (result.rpc_msg) {
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
        try testing.expect(req.hasId());
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
        try testing.expect(@TypeOf(result.rpc_msg) == RpcMessage);
        try testing.expect(result.rpc_msg == .request);
        switch (result.rpc_msg) {
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
        try testing.expect(req.hasId());
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


// Test handler registration.

fn fun0(alloc: Allocator) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, "Hello", .{});
}

fn fun1(alloc: Allocator, p1: Value) anyerror![]const u8 {
    const n1 = p1.string;
    const str = try allocPrint(alloc, "Hello {s}", .{n1});
    defer alloc.free(str);
    return std.json.stringifyAlloc(alloc, str, .{});
}

fn fun2(alloc: Allocator, p1: Value, p2: Value) anyerror![]const u8 {
    const n1 = p1.integer;
    const n2 = p2.integer;
    return std.json.stringifyAlloc(alloc, n1 - n2, .{});
}

fn fun2a(alloc: Allocator, p1: Value, p2: Value) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, (p1.integer - p2.integer) * 2, .{});
}

fn fun3(alloc: Allocator, p1: Value, p2: Value, p3: Value) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, p1.integer + p2.integer + p3.integer, .{});
}

fn fun9(alloc: Allocator, p1: Value, p2: Value, p3: Value, p4: Value,
        p5: Value, p6: Value, p7: Value, p8: Value, p9: Value) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc,
                                   p1.integer + p2.integer + p3.integer + p4.integer +
                                   p5.integer + p6.integer + p7.integer + p8.integer + p9.integer,
                                   .{});
}

fn funArray(alloc: Allocator, array: Array) anyerror![]const u8 {
    const str = try allocPrint(alloc, "Hello {}", .{array});
    defer alloc.free(str);
    return std.json.stringifyAlloc(alloc, str, .{});
}

fn addArray(alloc: Allocator, array: Array) anyerror![]const u8 {
    var sum: isize = 0;
    for (array.items) |value| {
        sum += value.integer;
    }
    return std.json.stringifyAlloc(alloc, sum, .{});
}

const MyErrors = error {
    MissingName,
};

fn funObj(alloc: Allocator, map: ObjectMap) anyerror![]const u8 {
    if (map.get("name")) |name| {
        const str = try allocPrint(alloc, "Hello {s}", .{name.string});
        defer alloc.free(str);
        return std.json.stringifyAlloc(alloc, str, .{});
    } else {
        return MyErrors.MissingName;
    }
}

fn fun_too_many_params(_: Allocator, p1: Value, p2: Value, p3: Value, p4: Value, p5: Value,
                       p6: Value, p7: Value, p8: Value, p9: Value, p10: Value) anyerror![]const u8 {
    _=p1; _=p2; _=p3; _=p4; _=p5; _=p6; _=p7; _=p8; _=p9; _=p10;
}

fn fun_missing_allocator() void {}

fn fun_wrong_return_type(_: Allocator) void {}

fn fun_wrong_param_type(alloc: Allocator, _: u8) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, "Hello", .{});
}

fn fun_wrong_param_type2(alloc: Allocator, _: Value, _: u8) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc, "Hello", .{});
}

test "Register handlers" {
    const alloc = gpa.allocator();
    {
        var registry = zigjr.Registry.init(alloc);
        defer registry.deinit();

        try registry.register("fun0", fun0);
        try testing.expect(registry.get("fun0") != null);
        try registry.register("fun1", fun1);
        try registry.register("subtract", fun2);
        try registry.register("sum3", fun3);
        try registry.register("sum9", fun9);
        try registry.register("funArray", funArray);
        try registry.register("funObj", funObj);

        // Re-register handler
        try registry.register("fun2", fun2a);
        try testing.expect(registry.get("fun2") != null);
        try testing.expect(registry.get("fun2").?.fn2 != fun2);
        try testing.expect(registry.get("fun2").?.fn2 == fun2a);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test validation on registering handler with too many params, expect error" {
    const alloc = gpa.allocator();
    {
        var registry = zigjr.Registry.init(alloc);
        defer registry.deinit();
        try testing.expectError(zigjr.RegistrationErrors.HandlerTooManyParams,
                                registry.register("fun_too_many_params", fun_too_many_params));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test validation on registering handler with the wrong param type, expect error" {
    const alloc = gpa.allocator();
    {
        var registry = zigjr.Registry.init(alloc);
        defer registry.deinit();
        try testing.expectError(zigjr.RegistrationErrors.HandlerInvalidParameterType,
                                registry.register("fun_wrong_param_type", fun_wrong_param_type));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test validation on registering a reserved name prefix 'rpc.', expect error" {
    const alloc = gpa.allocator();
    {
        var registry = zigjr.Registry.init(alloc);
        defer registry.deinit();
        try testing.expectError(zigjr.RegistrationErrors.InvalidMethodName,
                                registry.register("rpc.abc", fun0));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test validation on registering a handler with missing allocator, expect error" {
    const alloc = gpa.allocator();
    {
        var registry = zigjr.Registry.init(alloc);
        defer registry.deinit();
        try testing.expectError(zigjr.RegistrationErrors.MissingAllocator,
                                registry.register("fun_missing_allocator", fun_missing_allocator));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Uncomment to test catching registration errors on compile, expect compile error" {
    const alloc = gpa.allocator();
    {
        var registry = zigjr.Registry.init(alloc);
        defer registry.deinit();
        // These would cause compile errors, as expected.
        // try registry.register("fun_wrong_return_type", fun_wrong_return_type);
        // try registry.register("fun_wrong_param_type2", fun_wrong_param_type2);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

// Test request dispatching

fn registerFunctions(alloc: Allocator) !zigjr.Registry {
    var registry = zigjr.Registry.init(alloc);
    try registry.register("fun0", fun0);
    try registry.register("fun1", fun1);
    try registry.register("subtract", fun2);
    try registry.register("sum3", fun3);
    try registry.register("sum9", fun9);
    try registry.register("funArray", funArray);
    try registry.register("funObj", funObj);
    try registry.register("addArray", addArray);

    // std.debug.print("addArray handler: {any}\n", .{registry.get("addArray")});

    return registry;
}

test "Dispatching to 0-parameter method" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0", "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqualSlices(u8, parsed.value.object.get("result").?.string, "Hello");
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);

        // std.debug.print("response: {s}\n", .{response});
        // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("result").?});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to 2-integer parameter method" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqual(parsed.value.object.get("result").?.integer, 20);
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);

        // std.debug.print("response: {s}\n", .{response});
        // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("result").?});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to 1-string parameter method" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqualSlices(u8, parsed.value.object.get("result").?.string, "Hello FUN1");
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to 3-integer parameter method" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "sum3", "params": [1, 2, 3], "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqual(parsed.value.object.get("result").?.integer, 6);
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to 9-integer parameter method" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "sum9", "params": [1, 2, 3, 4, 5, 6, 7, 8, 9], "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqual(parsed.value.object.get("result").?.integer, 45);
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to an array-based parameter method" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "addArray", "params": [1, 2, 3, 4, 5, 6, 7, 8, 9], "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqual(parsed.value.object.get("result").?.integer, 45);
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to an object-based parameter method" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "funObj", "params": {"name": "abc"}, "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqualSlices(u8, parsed.value.object.get("result").?.string, "Hello abc");
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
        // std.debug.print("response: {s}\n", .{response});
        // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("result").?});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to an object-based parameter method without the needed value, expect error" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "funObj", "params": {"no-name": "abc"}, "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqual(parsed.value.object.get("error").?.object.get("code").?.integer, @intFromEnum(ErrorCode.ServerError));
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);
        // std.debug.print("response: {s}\n", .{response});
        // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("result").?});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to non-existing method, expect error" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "no-method"}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqual(parsed.value.object.get("error").?.object.get("code").?.integer, @intFromEnum(ErrorCode.MethodNotFound));
        try testing.expectEqual(parsed.value.object.get("id").?.null, {});

        // std.debug.print("response: {s}\n", .{response});
        // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("id").?});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to 0-parameter method with mismatched parameter count, expect error" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0", "params": [1], "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqual(parsed.value.object.get("error").?.object.get("code").?.integer, @intFromEnum(ErrorCode.InvalidParams));
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);

        // std.debug.print("response: {s}\n", .{response});
        // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("id").?});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to 0-parameter method with empty parameter array" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var result = zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0", "params": [], "id": 1}
        );
        defer result.deinit();

        const response = try registry.run(try result.request());
        defer registry.freeResponse(response);

        const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
        defer parsed.deinit();
        try testing.expectEqualSlices(u8, parsed.value.object.get("result").?.string, "Hello");
        try testing.expectEqual(parsed.value.object.get("id").?.integer, 1);

        // std.debug.print("response: {s}\n", .{response});
        // std.debug.print("parsed: {any}\n", .{parsed.value.object.get("id").?});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Dispatching to 1-parameter method with mismatched parameters, expect error" {
    const alloc = gpa.allocator();
    {
        var registry = try registerFunctions(alloc);
        defer registry.deinit();

        var buffer = std.ArrayList(u8).init(alloc);
        defer buffer.deinit();

        for (0..10)|i| {
            if (i == 1) continue;
            buffer.clearRetainingCapacity();
            for (0..i)|j| {
                if (j != 0) try buffer.appendSlice(", ");
                try buffer.writer().print("{}", .{j});
            }
            const req_json = try allocPrint(alloc,
                \\{{"jsonrpc": "2.0", "method": "fun1", "params": [{s}], "id": 1}}
                , .{buffer.items});
            // std.debug.print("req_json: {s}\n", .{req_json});
            defer alloc.free(req_json);

            var result = zigjr.parseJson(alloc, req_json);
            defer result.deinit();

            const response = try registry.run(try result.request());
            defer registry.freeResponse(response);
            // std.debug.print("response: {s}\n", .{response});

            const parsed = try std.json.parseFromSlice(Value, alloc, response, .{});
            defer parsed.deinit();
            try testing.expectEqual(parsed.value.object.get("error").?.object.get("code").?.integer, @intFromEnum(ErrorCode.InvalidParams));
        }            
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


