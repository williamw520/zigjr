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

fn funObj(alloc: Allocator, map: ObjectMap) anyerror![]const u8 {
    const str = try allocPrint(alloc, "Hello {}", .{map});
    defer alloc.free(str);
    return std.json.stringifyAlloc(alloc, str, .{});
}

fn fun_too_many_params(_: Allocator, p1: Value, p2: Value, p3: Value, p4: Value, p5: Value,
                       p6: Value, p7: Value, p8: Value, p9: Value, p10: Value) anyerror![]const u8 {
    _=p1; _=p2; _=p3; _=p4; _=p5; _=p6; _=p7; _=p8; _=p9; _=p10;
}

fn fun_missing_allocator() void {}

fn fun_wrong_return_type(_: Allocator) void {}

fn fun_wrong_param_type(_: Allocator, _: u8) anyerror![]const u8 {}

fn fun_wrong_param_type2(_: Allocator, _: Value, _: u8) anyerror![]const u8 {}

test "Register handlers" {
    const alloc = gpa.allocator();

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

    // Test validation.
    try testing.expectError(zigjr.HandlerErrors.HandlerTooManyParams,
                            registry.register("fun_too_many_params", fun_too_many_params));

    try testing.expectError(zigjr.HandlerErrors.HandlerInvalidParameterType,
                            registry.register("fun_wrong_param_type", fun_wrong_param_type));

    try testing.expectError(zigjr.HandlerErrors.InvalidMethodName,
                            registry.register("rpc.abc", fun0));

    // These would cause compile errors, correctly as expected.
    // try registry.register("fun_missing_allocator", fun_missing_allocator);
    // try registry.register("fun_wrong_return_type", fun_wrong_return_type);
    // try registry.register("fun_wrong_param_type2", fun_wrong_param_type2);
}

test "Parsing valid request, single integer param, integer id" {
    const alloc = gpa.allocator();
    {
        var result = try zigjr.parseJson(alloc,
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
        var result = try zigjr.parseJson(alloc,
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
        var result = try zigjr.parseJson(alloc,
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
        var result = try zigjr.parseJson(alloc,
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
        var result = try zigjr.parseJson(alloc,
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
        var result = try zigjr.parseJson(alloc,
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
        var result = try zigjr.parseJson(alloc,
            \\{"jsonrpc": "2.0", "method": "fun0", "id": "5a" }
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(req.hasId());
        try testing.expect(std.mem.eql(u8, req.id.str, "5a"));
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Parse empty request, expect InvalidRequest error." {
    const alloc = gpa.allocator();
    {
        var result = try zigjr.parseJson(alloc,
            \\{}
        );
        defer result.deinit();
        const req = try result.request();
        try testing.expect(req.hasError());
        try testing.expect(req.err.?.code == zigjr.ErrorCode.InvalidRequest);
        try testing.expect(req.isErrorCode(zigjr.ErrorCode.InvalidRequest));

    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Message request parsing" {
    // const alloc = gpa.allocator();

    // const e_req1a = try zigjr.Request.init(alloc,
    //     \\{
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req1a.err_code, e_req1a.err_msg});
    // try testing.expect(e_req1a.hasError() == true);
    // try testing.expect(e_req1a.err_code == zigjr.ErrorCode.ParseError);

    // const e_req1b = try zigjr.Request.init(alloc,
    //     \\}
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req1b.err_code, e_req1b.err_msg});
    // try testing.expect(e_req1b.hasError() == true);
    // try testing.expect(e_req1b.err_code == zigjr.ErrorCode.ParseError);

    // const e_req1c = try zigjr.Request.init(alloc,
    //     ""
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req1c.err_code, e_req1c.err_msg});
    // try testing.expect(e_req1c.hasError() == true);
    // try testing.expect(e_req1c.err_code == zigjr.ErrorCode.ParseError);

    // const e_req2 = try zigjr.Request.init(alloc,
    //     \\{"foo": }
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req2.err_code, e_req2.err_msg});
    // try testing.expect(e_req2.hasError() == true);
    // try testing.expect(e_req2.err_code == zigjr.ErrorCode.InvalidRequest);

    // const e_req2a = try zigjr.Request.init(alloc,
    //     \\ foo abc 123
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req2a.err_code, e_req2a.err_msg});
    // try testing.expect(e_req2a.hasError() == true);
    // try testing.expect(e_req2a.err_code == zigjr.ErrorCode.ParseError);

    // const e_req2b = try zigjr.Request.init(alloc,
    //     \\{"foo":
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req2b.err_code, e_req2b.err_msg});
    // try testing.expect(e_req2b.hasError() == true);
    // try testing.expect(e_req2b.err_code == zigjr.ErrorCode.InvalidRequest);

    // const e_req3 = try zigjr.Request.init(alloc,
    //     \\{"jsonrpc": }
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req3.err_code, e_req3.err_msg});
    // try testing.expect(e_req3.hasError() == true);
    // try testing.expect(e_req3.err_code == zigjr.ErrorCode.ParseError);

    // const e_req3a = try zigjr.Request.init(alloc,
    //     \\{"jsonrpc": "2.0"}
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req3a.err_code, e_req3a.err_msg});
    // try testing.expect(e_req3a.hasError() == true);
    // try testing.expect(e_req3a.err_code == zigjr.ErrorCode.InvalidRequest);

    // const e_req4 = try zigjr.Request.init(alloc,
    //     \\{"jsonrpc": "2.0", "method": "foobar", "params": [], "params": [], "id": "4"}
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req4.err_code, e_req4.err_msg});
    // try testing.expect(e_req4.hasError() == true);
    // try testing.expect(e_req4.err_code == zigjr.ErrorCode.InvalidRequest);
    
    // const e_req5 = try zigjr.Request.init(alloc,
    //     \\{"jsonrpc": "0.0", "method": "", "params": [], "id": "5"}
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5.err_code, e_req5.err_msg});
    // try testing.expect(e_req5.hasError() == true);
    // try testing.expect(e_req5.err_code == zigjr.ErrorCode.InvalidRequest);

    // const e_req5a = try zigjr.Request.init(alloc,
    //     \\{"jsonrpc": "1.0", "method": "", "params": [], "id": "5a"}
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5a.err_code, e_req5a.err_msg});
    // try testing.expect(e_req5a.hasError() == true);
    // try testing.expect(e_req5a.err_code == zigjr.ErrorCode.InvalidRequest);

    // const e_req5b = try zigjr.Request.init(alloc,
    //     \\{"jsonrpc": "3.0", "method": "", "params": [], "id": "5b"}
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5b.err_code, e_req5b.err_msg});
    // try testing.expect(e_req5b.hasError() == true);
    // try testing.expect(e_req5b.err_code == zigjr.ErrorCode.InvalidRequest);

    // const e_req5c = try zigjr.Request.init(alloc,
    //     \\{"jsonrpc": "2.0", "method": "", "params": [], "id": "5c"}
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5c.err_code, e_req5c.err_msg});
    // try testing.expect(e_req5c.hasError() == true);
    // try testing.expect(e_req5c.err_code == zigjr.ErrorCode.InvalidRequest);

    // const e_req5d = try zigjr.Request.init(alloc,
    //     \\{"jsonrpc": "2.0", "method": "foobar", "params": 1234, "id": "5d"}
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5d.err_code, e_req5d.err_msg});
    // try testing.expect(e_req5d.hasError() == true);
    // try testing.expect(e_req5d.err_code == zigjr.ErrorCode.InvalidParams);

    // const e_req5e = try zigjr.Request.init(alloc,
    //     \\{"jsonrpc": "2.0", "method": "foobar", "params": "abcd", "id": "5e"}
    // );
    // std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5e.err_code, e_req5e.err_msg});
    // try testing.expect(e_req5e.hasError() == true);
    // try testing.expect(e_req5e.err_code == zigjr.ErrorCode.InvalidParams);

}

test "Request dispatching" {
    std.debug.print("-------- Request dispatching\n", .{});

    const alloc = gpa.allocator();

    var registry = zigjr.Registry.init(alloc);
    defer registry.deinit();

    try registry.register("fun0", fun0);
    try registry.register("fun1", fun1);
    try registry.register("subtract", fun2);


    // var json_stream1 = std.io.fixedBufferStream(
    //     \\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
    // );
    // const in_reader1 = json_stream1.reader();
    // var rs1 = zigjr.RpcParser(@TypeOf(in_reader1)).init(alloc, in_reader1);
    // defer rs1.deinit();

    // const req0 = try rs1.next();
    // _=req0;

    // const msg0 =\\{"jsonrpc": "2.0", "method": "fun0", "params": [20, 10], "id": 1}
    //             ;
    
    var result0 = try zigjr.parseJson(alloc,
        \\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
    );
    defer result0.deinit();
    std.debug.print("result0: {any}\n", .{result0.rpc_msg});

    // std.debug.print("req0.body: {any}\n", .{req0.body});
    // const res0 = try registry.run(req0);
    // std.debug.print("res0 {s}\n", .{res0});
    
    // const msg1 =\\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": 1}
    //             ;
    // const req1 = try zigjr.Request.init(allocator, msg1);
    // std.debug.print("req1.body: {any}\n", .{req1.body});
    // const res1 = try registry.run(req1);
    // std.debug.print("res1 {s}\n", .{res1});
    
    // const msg2 =\\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
    //             ;
    // const req2 = try zigjr.Request.init(allocator, msg2);
    // std.debug.print("req2.body: {any}\n", .{req2.body});
    // if (req2.body) |body| {
    //     std.debug.print("req2.body.params: {any}\n", .{body.params});
    //     const p1: Value = body.params.array.items[0];
    //     std.debug.print("req2.body.params[0]: {any}\n", .{p1});
    // }
    // const res2 = try registry.run(req2);
    // std.debug.print("res2 {s}\n", .{res2});
    
    // const msg3 =\\{"jsonrpc": "2.0", "method9": "no-method", "params": [42, 22], "id": 1}
    //             ;
    // const req3 = try zigjr.Request.init(allocator, msg3);
    // std.debug.print("req3.body: {any}\n", .{req3.body});
    // const res3 = try registry.run(req3);
    // std.debug.print("res3 {s}\n", .{res3});
    
}

test "Request streaming" {
    std.debug.print("-------- Request streaming\n", .{});

    const alloc = gpa.allocator();

    var json_stream1 = std.io.fixedBufferStream(
        \\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
    );
    const in_reader1 = json_stream1.reader();
    var result1 = try zigjr.parseReader(alloc, in_reader1);
    defer result1.deinit();
    std.debug.print("result1: {any}\n", .{result1.rpc_msg});

    // var json_stream2 = std.io.fixedBufferStream(
    //     \\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
    // );
    // var rs2 = zigjr.parseReader(alloc, json_stream2.reader());
    // defer rs2.deinit();

    // var json_stream3 = std.io.fixedBufferStream(
    //     \\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
    // );
    // var rs3 = zigjr.parseReader(alloc, json_stream3.reader());
    // defer rs3.deinit();

    // const rm3 = try rs3.next();
    // std.debug.print("rm3 {any}\n", .{rm3});
    // std.debug.print("rm3 {s}\n", .{rm3.request.body.method});
    // std.debug.print("rm3 {any}\n", .{rm3.request.body.params});


    // var json_stream4 = std.io.fixedBufferStream(
    //     \\[ {"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1},
    //     \\  {"jsonrpc": "2.0", "method": "add", "params": [2, 3], "id": 2} ]
    // );
    // var rs4 = zigjr.parseReader(alloc, json_stream4.reader());
    // defer rs4.deinit();

    // const rm4 = try rs4.next();
    // std.debug.print("rm4 {any}\n", .{rm4});
    // std.debug.print("rm4 {s}\n", .{rm4.batch[0].body.method});
    // std.debug.print("rm4 {any}\n", .{rm4.batch[0].body.params});
    // std.debug.print("rm4 {s}\n", .{rm4.batch[1].body.method});
    // std.debug.print("rm4 {any}\n", .{rm4.batch[1].body.params});


    // var json_stream5 = std.io.fixedBufferStream(
    //     \\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 1}
    //     \\  {"jsonrpc": "2.0", "method": "add", "params": [2, 3], "id": 2}
    // );
    // var rs5 = zigjr.parseReader(alloc, json_stream5.reader());
    // defer rs5.deinit();

    // // NOTE: Stream parsing of JSON's is impossible.
    // // The next statement causes an assert in std.json.parseFromTokenSourceLeaky(),
    // //  assert(.end_of_document == try scanner_or_reader.next())
    // // It's expecting the end of input after parsed one JSON.
    // std.debug.print("--------\n", .{});
    // // const rm5 = rs5.next() catch |err| {
    // //     std.debug.print("rm5 err: {any}\n", .{err});
    // // };
    // // std.debug.print("rm5 {any}\n", .{rm5});
    
    // // std.debug.print("rm5 {s}\n", .{rm5.batch[0].method});
    // // std.debug.print("rm5 {any}\n", .{rm5.batch[0].params});
    // // std.debug.print("rm5 {s}\n", .{rm5.batch[1].method});
    // // std.debug.print("rm5 {any}\n", .{rm5.batch[1].params});
    
}



