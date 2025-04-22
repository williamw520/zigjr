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


