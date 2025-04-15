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
    const allocator = gpa.allocator();

    var registry = zigjr.Registry.init(allocator);
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
    try testing.expectError(zigjr.ServerErrors.HandlerTooManyParams,
                            registry.register("fun_too_many_params", fun_too_many_params));

    try testing.expectError(zigjr.ServerErrors.HandlerInvalidParameterType,
                            registry.register("fun_wrong_param_type", fun_wrong_param_type));

    try testing.expectError(zigjr.ServerErrors.InvalidMethodName,
                            registry.register("rpc.abc", fun0));

    // These would cause compile errors, correctly as expected.
    // try registry.register("fun_missing_allocator", fun_missing_allocator);
    // try registry.register("fun_wrong_return_type", fun_wrong_return_type);
    // try registry.register("fun_wrong_param_type2", fun_wrong_param_type2);
}

test "Message request parsing" {
    const allocator = gpa.allocator();

    var registry = zigjr.Registry.init(allocator);
    defer registry.deinit();

    try registry.register("fun0", fun0);
    try registry.register("fun1", fun1);
    try registry.register("subtract", fun2);

    const msg0 =\\{"jsonrpc": "2.0", "method": "fun0", "params": [], "id": 0}
                ;
    const req0 = try zigjr.Request.init(allocator, msg0);
    try testing.expect(req0.hasError() == false);
    try testing.expect(req0.getId().num == 0);
    
    const msg1 =\\{"jsonrpc": "2.0", "method": "fun1", "params": ["FUN1"], "id": "1"}
                ;
    const req1 = try zigjr.Request.init(allocator, msg1);
    try testing.expect(req1.hasError() == false);
    try testing.expect(std.mem.eql(u8, req1.getId().str, "1"));

    const msg2 =\\{"jsonrpc": "2.0", "method": "subtract", "params": [42, 22], "id": 2}
                ;
    const req2 = try zigjr.Request.init(allocator, msg2);
    try testing.expect(req2.hasError() == false);
    try testing.expect(req2.getId().num == 2);

    const msg3 =\\{"jsonrpc": "2.0", "method": "fun_obj", "params": { "name": "foobar", "weight": 150 }, "id": 3}
                ;
    const req3 = try zigjr.Request.init(allocator, msg3);
    try testing.expect(req3.hasError() == false);
    try testing.expect(req3.getId().num == 3);

    const msg4 =\\{"jsonrpc": "2.0", "method": "fun0", "params": [] }
                ;
    const req4 = try zigjr.Request.init(allocator, msg4);
    try testing.expect(req4.hasError() == false);
    try testing.expect(req4.getId() == zigjr.IdType.nul);

    const msg5 =\\{"jsonrpc": "2.0", "method": "fun0" }
                ;
    const req5 = try zigjr.Request.init(allocator, msg5);
    try testing.expect(req5.hasError() == false);
    try testing.expect(req5.getId() == zigjr.IdType.nul);

    const msg5a =\\{"jsonrpc": "2.0", "method": "fun0", "id": "5a" }
                ;
    const req5a = try zigjr.Request.init(allocator, msg5a);
    try testing.expect(req5a.hasError() == false);
    try testing.expect(std.mem.eql(u8, req5a.getId().str, "5a"));

    const msg5b =\\{"jsonrpc": "2.0", "method": "fun0", "params": [], "id": "5b" }
                ;
    const req5b = try zigjr.Request.init(allocator, msg5b);
    try testing.expect(req5b.hasError() == false);
    try testing.expect(std.mem.eql(u8, req5b.getId().str, "5b"));


    const e_msg1 =\\{}
                ;
    const e_req1 = try zigjr.Request.init(allocator, e_msg1);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req1.err_code, e_req1.err_msg});
    try testing.expect(e_req1.hasError() == true);
    try testing.expect(e_req1.err_code == zigjr.ErrorCode.InvalidRequest);

    const e_msg1a =\\{
                ;
    const e_req1a = try zigjr.Request.init(allocator, e_msg1a);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req1a.err_code, e_req1a.err_msg});
    try testing.expect(e_req1a.hasError() == true);
    try testing.expect(e_req1a.err_code == zigjr.ErrorCode.ParseError);

    const e_msg1b =\\}
                ;
    const e_req1b = try zigjr.Request.init(allocator, e_msg1b);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req1b.err_code, e_req1b.err_msg});
    try testing.expect(e_req1b.hasError() == true);
    try testing.expect(e_req1b.err_code == zigjr.ErrorCode.ParseError);

    const e_msg1c ="";
    const e_req1c = try zigjr.Request.init(allocator, e_msg1c);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req1c.err_code, e_req1c.err_msg});
    try testing.expect(e_req1c.hasError() == true);
    try testing.expect(e_req1c.err_code == zigjr.ErrorCode.ParseError);

    const e_msg2 =\\{"foo": }
                ;
    const e_req2 = try zigjr.Request.init(allocator, e_msg2);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req2.err_code, e_req2.err_msg});
    try testing.expect(e_req2.hasError() == true);
    try testing.expect(e_req2.err_code == zigjr.ErrorCode.InvalidRequest);

    const e_msg2a =\\ foo abc 123
                ;
    const e_req2a = try zigjr.Request.init(allocator, e_msg2a);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req2a.err_code, e_req2a.err_msg});
    try testing.expect(e_req2a.hasError() == true);
    try testing.expect(e_req2a.err_code == zigjr.ErrorCode.ParseError);

    const e_msg2b =\\{"foo":
                ;
    const e_req2b = try zigjr.Request.init(allocator, e_msg2b);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req2b.err_code, e_req2b.err_msg});
    try testing.expect(e_req2b.hasError() == true);
    try testing.expect(e_req2b.err_code == zigjr.ErrorCode.InvalidRequest);

    const e_msg3 =\\{"jsonrpc": }
                ;
    const e_req3 = try zigjr.Request.init(allocator, e_msg3);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req3.err_code, e_req3.err_msg});
    try testing.expect(e_req3.hasError() == true);
    try testing.expect(e_req3.err_code == zigjr.ErrorCode.ParseError);

    const e_msg3a =\\{"jsonrpc": "2.0"}
                ;
    const e_req3a = try zigjr.Request.init(allocator, e_msg3a);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req3a.err_code, e_req3a.err_msg});
    try testing.expect(e_req3a.hasError() == true);
    try testing.expect(e_req3a.err_code == zigjr.ErrorCode.InvalidRequest);

    const e_msg4 =\\{"jsonrpc": "2.0", "method": "foobar", "params": [], "params": [], "id": "4"}
                ;
    const e_req4 = try zigjr.Request.init(allocator, e_msg4);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req4.err_code, e_req4.err_msg});
    try testing.expect(e_req4.hasError() == true);
    try testing.expect(e_req4.err_code == zigjr.ErrorCode.InvalidRequest);
    
    const e_msg5 =\\{"jsonrpc": "0.0", "method": "", "params": [], "id": "5"}
                ;
    const e_req5 = try zigjr.Request.init(allocator, e_msg5);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5.err_code, e_req5.err_msg});
    try testing.expect(e_req5.hasError() == true);
    try testing.expect(e_req5.err_code == zigjr.ErrorCode.InvalidRequest);

    const e_msg5a =\\{"jsonrpc": "1.0", "method": "", "params": [], "id": "5a"}
                ;
    const e_req5a = try zigjr.Request.init(allocator, e_msg5a);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5a.err_code, e_req5a.err_msg});
    try testing.expect(e_req5a.hasError() == true);
    try testing.expect(e_req5a.err_code == zigjr.ErrorCode.InvalidRequest);

    const e_msg5b =\\{"jsonrpc": "3.0", "method": "", "params": [], "id": "5b"}
                ;
    const e_req5b = try zigjr.Request.init(allocator, e_msg5b);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5b.err_code, e_req5b.err_msg});
    try testing.expect(e_req5b.hasError() == true);
    try testing.expect(e_req5b.err_code == zigjr.ErrorCode.InvalidRequest);

    const e_msg5c =\\{"jsonrpc": "2.0", "method": "", "params": [], "id": "5c"}
                ;
    const e_req5c = try zigjr.Request.init(allocator, e_msg5c);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5c.err_code, e_req5c.err_msg});
    try testing.expect(e_req5c.hasError() == true);
    try testing.expect(e_req5c.err_code == zigjr.ErrorCode.InvalidRequest);

    const e_msg5d =\\{"jsonrpc": "2.0", "method": "foobar", "params": 1234, "id": "5d"}
                ;
    const e_req5d = try zigjr.Request.init(allocator, e_msg5d);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5d.err_code, e_req5d.err_msg});
    try testing.expect(e_req5d.hasError() == true);
    try testing.expect(e_req5d.err_code == zigjr.ErrorCode.InvalidParams);

    const e_msg5e =\\{"jsonrpc": "2.0", "method": "foobar", "params": "abcd", "id": "5e"}
                ;
    const e_req5e = try zigjr.Request.init(allocator, e_msg5e);
    std.debug.print("err_code: {}, err_msg: {s}\n", .{e_req5e.err_code, e_req5e.err_msg});
    try testing.expect(e_req5e.hasError() == true);
    try testing.expect(e_req5e.err_code == zigjr.ErrorCode.InvalidParams);

}

test "Request dispatching" {
    // std.debug.print("\n\n\n", .{});
    // std.debug.print("test handler calls...\n", .{});

    // const allocator = gpa.allocator();

    // var registry = zigjr.Registry.init(allocator);
    // defer registry.deinit();

    // try registry.register("fun0", fun0);
    // try registry.register("fun1", fun1);
    // try registry.register("subtract", fun2);

    // const msg0 =\\{"jsonrpc": "2.0", "method": "fun0", "params": [], "id": 1}
    //             ;
    // const req0 = try zigjr.Request.init(allocator, msg0);
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

