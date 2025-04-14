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

    _=return_type;
    _=param_count;

    // std.debug.print("TypeOf: {any}\n", .{type_foo});
    // std.debug.print("typeInfo: {any}\n", .{info_foo});
    // std.debug.print("info_fn: {any}\n", .{info_fn_foo});
    // std.debug.print("return_type: {any}\n", .{return_type});
    // std.debug.print("param_count: {any}\n", .{param_count});
    // std.debug.print("params[0]: {any}\n", .{params[0]});
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

fn fun9(alloc: Allocator, p1: Value, p2: Value, p3: Value, p4: Value, p5: Value, p6: Value, p7: Value, p8: Value, p9: Value) anyerror![]const u8 {
    return std.json.stringifyAlloc(alloc,
                                   p1.integer + p2.integer + p3.integer + p4.integer + p5.integer + p6.integer + p7.integer + p8.integer + p9.integer,
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

fn fun_too_many_params(_: Allocator, p1: Value, p2: Value, p3: Value, p4: Value, p5: Value, p6: Value, p7: Value, p8: Value, p9: Value, p10: Value) anyerror![]const u8 {
    _=p1; _=p2; _=p3; _=p4; _=p5; _=p6; _=p7; _=p8; _=p9; _=p10;
}

fn fun_missing_allocator() void {
}

fn fun_wrong_return_type(_: Allocator) void {
}

fn fun_wrong_param_type(_: Allocator, _: u8) anyerror![]const u8 {
}

fn fun_wrong_param_type2(_: Allocator, _: Value, _: u8) anyerror![]const u8 {
}

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

    // These would cause compile errors, correctly as expected.
    // try registry.register("fun_missing_allocator", fun_missing_allocator);
    // try registry.register("fun_wrong_return_type", fun_wrong_return_type);
    // try registry.register("fun_wrong_param_type2", fun_wrong_param_type2);
}

test "Register handlers and message handling" {
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

