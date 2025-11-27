const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const StringHashMap = std.hash_map.StringHashMap;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;

const zigjr = @import("../zigjr.zig");
const json_call = zigjr.json_call;
const DispatchResult = zigjr.DispatchResult;
const DispatchCtx = zigjr.DispatchCtx;


const ReqUserData = struct {
    x: i64 = 10,
};

var fn0_called = false;
var fn0_with_err_called = false;
var fn0_alloc_called = false;

fn fn0() void {
    // std.debug.print("fn0() called\n", .{});
    fn0_called = true;
}

fn fn0_with_err() !void {
    // std.debug.print("fn0_with_err() called\n", .{});
    fn0_with_err_called = true;
}

fn fn0_return_value() []const u8 {
    // std.debug.print("fn0_return_value() called\n", .{});
    return "Hello";
}

fn fn0_return_value_with_err() ![]const u8 {
    // std.debug.print("fn0_return_value_with_err() called\n", .{});
    return "Hello";
}

fn fn0_return_json_str() zigjr.JsonStr {
    return .{
        .json = "{ \"foobar\": 42 }",
    };
}

fn fn0_return_json_str_err(alloc: Allocator) !zigjr.JsonStr {
    const json = try alloc.dupe(u8, "{ \"foobar\": 42 }");
    return .{
        .json = json,
    };
}

fn fn0_alloc(alloc: Allocator) !void {
    // std.debug.print("fn0_alloc() called\n", .{});
    // The arena allocator will take care of freeing it.
    _ = try alloc.dupe(u8, "Hello. Allocate some memory without freeing.");
    fn0_alloc_called = true;
}


var fn1_integer_called = false;
var fn1_float_called = false;
var fn1_bool_called = false;
var fn1_string_called = false;
var fn1_with_err_called = false;
var fn1_alloc_with_err_called = false;

fn fn1_integer(a: i64) void {
    _=a;
    // std.debug.print("fn1_integer() called, a:{}\n", .{a});
    fn1_integer_called = true;
}

fn fn1_float(a: f64) void {
    _=a;
    // std.debug.print("fn1_float() called, a:{}\n", .{a});
    fn1_float_called = true;
}

fn fn1_bool(a: bool) void {
    _=a;
    // std.debug.print("fn1_bool() called, a:{}\n", .{a});
    fn1_bool_called = true;
}

fn fn1_string(a: []const u8) void {
    _=a;
    // std.debug.print("fn1_string() called, a:{}\n", .{a});
    fn1_string_called = true;
}

fn fn1_with_err(a: i64) !void {
    _=a;
    // std.debug.print("fn1_with_err() called, a:{}\n", .{a});
    fn1_with_err_called = true;
}

fn fn1_alloc_with_err(alloc: Allocator, a: i64) !void {
    _=a;
    // std.debug.print("fn1_alloc_with_err() called, a:{}\n", .{a});
    // The arena allocator will take care of freeing it.
    _ = try alloc.dupe(u8, "Hello. Allocate some memory without freeing.");
    fn1_alloc_with_err_called = true;
}

fn fn1_with_dresult_none(a: i64) DispatchResult {
    _=a;
    return DispatchResult.asNone();
}

fn fn1_with_dresult_integer(a: i64) DispatchResult {
    _=a;
    const json = "123";
    return DispatchResult.withResult(json);
}

fn fn1_with_dresult_integer_err(alloc: Allocator, a: i64) !DispatchResult {
    const json = try std.json.Stringify.valueAlloc(alloc, a, .{});
    return DispatchResult.withResult(json);
}

fn fn1_with_dresult_str_err(alloc: Allocator, a: i64) !DispatchResult {
    _=a;
    const result = "abc";
    const json = try std.json.Stringify.valueAlloc(alloc, result, .{});
    return DispatchResult.withResult(json);
}


var fn4_called = false;

fn fn4(a: i64, b: f64, c: bool, d: []const u8) void {
    _=a;
    _=b;
    _=c;
    _=d;
    // std.debug.print("fn4_integer() called, a:{}, b:{}, c:{}, d:{s}\n", .{a, b, c, d});
    fn4_called = true;
}


var fn_cat_called = false;

const CatInfo = struct {
    cat_name: []const u8,
    weight: f64,
    eye_color: []const u8,
};

fn fn_cat(a: CatInfo) void {
    _=a;
    // std.debug.print("fn4_integer() called, a:{any}\n", .{a});
    fn_cat_called = true;
}

fn fn_cat_value(json_value: std.json.Value) CatInfo {
    std.debug.print("fn_cat_value() called\n", .{});
    fn_cat_called = true;
    return .{
        .cat_name = json_value.object.get("cat_name").?.string,
        .weight = json_value.object.get("weight").?.float,
        .eye_color = json_value.object.get("eye_color").?.string,
    };
}


var fn_opt1_int_a: ?isize = null;

fn fn_opt1_int(a: ?isize) void {
    // std.debug.print("fn_opt1_int called, a:{any}\n", .{a});
    fn_opt1_int_a = a;
}

var fn_opt1_str_a: ?[]const u8 = null;

fn fn_opt1_str(alloc: Allocator, a: ?[]const u8) ![]const u8 {
    // std.debug.print("fn_opt1_str called, a:{any}\n", .{a});
    fn_opt1_str_a = a;
    if (a)|str| {
        return str;
    } else {
        return try allocPrint(alloc, "a is null", .{});
    }
}

var fn_opt1_cat_a: ?CatInfo = null;

fn fn_opt1_cat(a: ?CatInfo) void {
    // std.debug.print("fn_opt1_cat called, a:{any}\n", .{a});
    fn_opt1_cat_a = a;
}


test "Test rpc call on fn0." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var dc: DispatchCtx = .{
        .arena = arena_alloc,
        .logger = nop_logger.asLogger(),
    };
    var ctx = {};

    {
        var h = json_call.makeRpcHandler(&ctx, fn0);
        fn0_called = false;
        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn0_called);
        fn0_called = false;

        _ = try h.invokeJson(&dc, "");
        try testing.expect(fn0_called);
        fn0_called = false;

        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn0_called);
        fn0_called = false;

        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn0_called);
        fn0_called = false;
    }

    {
        var h = json_call.makeRpcHandler(&ctx, fn0_with_err);
        fn0_with_err_called = false;

        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn0_with_err_called);
        fn0_with_err_called = false;

        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn0_with_err_called);
        fn0_with_err_called = false;

        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn0_with_err_called);
        fn0_with_err_called = false;

        const dresult = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn0_with_err_called);
        fn0_with_err_called = false;
        try testing.expect(dresult == .none);
    }

    {
        var h = json_call.makeRpcHandler(&ctx, fn0_return_json_str);
        _ = try h.invoke(&dc, .{ .null = {} });
        _ = try h.invoke(&dc, .{ .null = {} });
        _ = try h.invokeJson(&dc, "");
        const dresult = try h.invoke(&dc, .{ .null = {} });
        // std.debug.print("result {s}\n", .{dresult.result});
        try testing.expectEqualSlices(u8, dresult.result, "{ \"foobar\": 42 }");
    }

    {
        var h = json_call.makeRpcHandler(&ctx, fn0_return_json_str_err);
        _ = try h.invoke(&dc, .{ .null = {} });
        _ = try h.invoke(&dc, .{ .null = {} });
        _ = try h.invokeJson(&dc, "");
        const dresult = try h.invoke(&dc, .{ .null = {} });
        // std.debug.print("result {s}\n", .{dresult.result});
        try testing.expectEqualSlices(u8, dresult.result, "{ \"foobar\": 42 }");
    }

    {
        var h = json_call.makeRpcHandler(&ctx, fn0_alloc);
        fn0_alloc_called = false;

        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn0_alloc_called);
        fn0_alloc_called = false;

        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn0_alloc_called);
        fn0_alloc_called = false;

        _ = try h.invokeJson(&dc, "");
        try testing.expect(fn0_alloc_called);
        fn0_alloc_called = false;
    }
}


test "Test rpc call on fn1." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var dc: DispatchCtx = .{
        .arena = arena_alloc,
        .logger = nop_logger.asLogger(),
    };
    var ctx = {};

    {
        var h = json_call.makeRpcHandler(&ctx, fn1_integer);
        fn1_integer_called = false;

        _ = try h.invoke(&dc, .{ .integer = 123 });
        try testing.expect(fn1_integer_called);
        fn1_integer_called = false;

        _ = try h.invokeJson(&dc, "123");
        try testing.expect(fn1_integer_called);
        fn1_integer_called = false;

        var array = std.json.Array.init(alloc);
        try array.append(.{ .integer = 456 });
        defer array.deinit();
        _ = try h.invoke(&dc, .{ .array = array });
        try testing.expect(fn1_integer_called);
        fn1_integer_called = false;

        _ = try h.invokeJson(&dc, "[123]");
        try testing.expect(fn1_integer_called);
        fn1_integer_called = false;
    }
    {
        var h = json_call.makeRpcHandler(&ctx, fn1_alloc_with_err);
        _ = try h.invoke(&dc, .{ .integer = 123 });
        try testing.expect(fn1_alloc_with_err_called);
        fn1_alloc_with_err_called = false;

        _ = try h.invokeJson(&dc, "123");
        try testing.expect(fn1_alloc_with_err_called);
    }

    {
        var h = json_call.makeRpcHandler(&ctx, fn1_float);
        _ = try h.invoke(&dc, .{ .float = 1.23 });
        _ = try h.invokeJson(&dc, "1.23");
    }
    {
        var h = json_call.makeRpcHandler(&ctx, fn1_float);
        var array = std.json.Array.init(alloc);
        try array.append(.{ .float = 4.56 });
        defer array.deinit();
        fn1_float_called = false;
        
        _ = try h.invoke(&dc, .{ .array = array });
        try testing.expect(fn1_float_called);
        fn1_float_called = false;
        
        _ = try h.invokeJson(&dc, "[1.23]");
        try testing.expect(fn1_float_called);
        fn1_float_called = false;
    }
    
    {
        var h = json_call.makeRpcHandler(&ctx, fn1_bool);
        fn1_bool_called = false;

        _ = try h.invoke(&dc, .{ .bool = true });
        try testing.expect(fn1_bool_called);
        fn1_bool_called = false;
        
        _ = try h.invokeJson(&dc, "true");
        try testing.expect(fn1_bool_called);
        fn1_bool_called = false;
    }
    {
        var h = json_call.makeRpcHandler(&ctx, fn1_bool);
        var array = std.json.Array.init(alloc);
        try array.append(.{ .bool = false });
        defer array.deinit();
        fn1_bool_called = false;

        _ = try h.invoke(&dc, .{ .array = array });
        try testing.expect(fn1_bool_called);
        fn1_bool_called = false;
        
        _ = try h.invokeJson(&dc, "[false]");
        try testing.expect(fn1_bool_called);
        fn1_bool_called = false;
        
    }
    
    {
        var h = json_call.makeRpcHandler(&ctx, fn1_string);
        fn1_string_called = false;

        _ = try h.invoke(&dc, .{ .string = "Hello123" });
        try testing.expect(fn1_string_called);
        fn1_string_called = false;

        _ = try h.invokeJson(&dc, "\"Hello123\"");
        try testing.expect(fn1_string_called);
        fn1_string_called = false;
    }
    {
        var h = json_call.makeRpcHandler(&ctx, fn1_string);
        var array = std.json.Array.init(alloc);
        try array.append(.{ .string = "Hello456" });
        defer array.deinit();
        fn1_string_called = false;
        
        _ = try h.invoke(&dc, .{ .array = array });
        try testing.expect(fn1_string_called);
        fn1_string_called = false;
        
        _ = try h.invokeJson(&dc, "[\"Hello456\"]");
        try testing.expect(fn1_string_called);
        fn1_string_called = false;
        
    }
}

test "Test rpc call on fn1 with DispatchResult." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var dc: DispatchCtx = .{
        .arena = arena_alloc,
        .logger = nop_logger.asLogger(),
    };
    var ctx = {};

    {
        var h = json_call.makeRpcHandler(&ctx, fn1_with_dresult_none);
        const dres = try h.invoke(&dc, .{ .integer = 123 });
        // std.debug.print("fn1_with_dresult_none: {any}\n", .{dres});
        try testing.expectEqual(dres, DispatchResult.none);
    }
    {
        var h = json_call.makeRpcHandler(&ctx, fn1_with_dresult_integer);
        const dres = try h.invoke(&dc, .{ .integer = 123 });
        try testing.expectEqualStrings(dres.result, "123");
    }
    {
        var h = json_call.makeRpcHandler(&ctx, fn1_with_dresult_integer_err);
        const dres = try h.invoke(&dc, .{ .integer = 123 });
        try testing.expectEqualStrings(dres.result, "123");
    }
    {
        var h = json_call.makeRpcHandler(&ctx, fn1_with_dresult_str_err);
        const dres = try h.invoke(&dc, .{ .integer = 123 });
        try testing.expectEqualStrings(dres.result, "\"abc\"");
    }
}

test "Test rpc call on fn4." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var dc: DispatchCtx = .{
        .arena = arena_alloc,
        .logger = nop_logger.asLogger(),
    };
    var ctx = {};

    {
        var h = json_call.makeRpcHandler(&ctx, fn4);
        _ = try h.invokeJson(&dc, "[123, 4.56, true, \"abc\"]");
        try testing.expect(fn4_called);
    }
}

test "Test rpc call on fn_cat." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var dc: DispatchCtx = .{
        .arena = arena_alloc,
        .logger = nop_logger.asLogger(),
    };
    var ctx = {};

    {
        var h = json_call.makeRpcHandler(&ctx, fn_cat);
        fn_cat_called = false;
        _ = try h.invokeJson(&dc, 
                \\{
                \\ "cat_name": "cat1",
                \\ "weight": 5.5,
                \\ "eye_color": "brown"
                \\}
        );
        try testing.expect(fn_cat_called);
    }
}

test "Test rpc call on fn_cat_value on std.json.Value parameter." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var dc: DispatchCtx = .{
        .arena = arena_alloc,
        .logger = nop_logger.asLogger(),
    };
    var ctx = {};

    {
        var h = json_call.makeRpcHandler(&ctx, fn_cat_value);
        fn_cat_called = false;
        _ = try h.invokeJson(&dc, 
                \\{
                \\ "cat_name": "cat1",
                \\ "weight": 5.5,
                \\ "eye_color": "brown"
                \\}
        );
        try testing.expect(fn_cat_called);
    }
}

test "Test rpc call on fn_opt1_int with optional argument." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var dc: DispatchCtx = .{
        .arena = arena_alloc,
        .logger = nop_logger.asLogger(),
    };
    var ctx = {};

    {
        var h = json_call.makeRpcHandler(&ctx, fn_opt1_int);

        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn_opt1_int_a == null);

        _ = try h.invoke(&dc, .{ .integer = 123 });
        try testing.expect(fn_opt1_int_a == 123);

        _ = try h.invokeJson(&dc, "");
        try testing.expect(fn_opt1_int_a == null);

        _ = try h.invokeJson(&dc, "123");
        try testing.expect(fn_opt1_int_a == 123);

        var array0 = std.json.Array.init(alloc);
        defer array0.deinit();
        _ = try h.invoke(&dc, .{ .array = array0 });
        try testing.expect(fn_opt1_int_a == null);

        var array1 = std.json.Array.init(alloc);
        try array1.append(.{ .integer = 456 });
        defer array1.deinit();
        _ = try h.invoke(&dc, .{ .array = array1 });
        try testing.expect(fn_opt1_int_a == 456);

        _ = try h.invokeJson(&dc, "[]");
        try testing.expect(fn_opt1_int_a == null);

        _ = try h.invokeJson(&dc, "[123]");
        try testing.expect(fn_opt1_int_a == 123);
    }
}

test "Test rpc call on fn_opt1_str with optional argument and alloc." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var dc: DispatchCtx = .{
        .arena = arena_alloc,
        .logger = nop_logger.asLogger(),
    };
    var ctx = {};

    {
        var h = json_call.makeRpcHandler(&ctx, fn_opt1_str);
        var res: DispatchResult = undefined;
        
        res = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn_opt1_str_a == null);
        try testing.expectEqualStrings(res.result, "\"a is null\"");

        res = try h.invoke(&dc, .{ .string = "abc" });
        try testing.expectEqualStrings(fn_opt1_str_a.?, "abc");
        try testing.expectEqualStrings(res.result, "\"abc\"");

        res = try h.invokeJson(&dc, "");
        try testing.expect(fn_opt1_str_a == null);
        try testing.expectEqualStrings(res.result, "\"a is null\"");

        res = try h.invokeJson(&dc, "\"abc\"");
        try testing.expectEqualStrings(fn_opt1_str_a.?, "abc");
        try testing.expectEqualStrings(res.result, "\"abc\"");

        var array0 = std.json.Array.init(alloc);
        defer array0.deinit();
        res = try h.invoke(&dc, .{ .array = array0 });
        try testing.expect(fn_opt1_str_a == null);
        try testing.expectEqualStrings(res.result, "\"a is null\"");

        var array1 = std.json.Array.init(alloc);
        try array1.append(.{ .string = "xyz" });
        defer array1.deinit();
        res = try h.invoke(&dc, .{ .array = array1 });
        try testing.expectEqualStrings(fn_opt1_str_a.?, "xyz");
        try testing.expectEqualStrings(res.result, "\"xyz\"");

        res = try h.invokeJson(&dc, "[]");
        try testing.expect(fn_opt1_str_a == null);
        try testing.expectEqualStrings(res.result, "\"a is null\"");

        res = try h.invokeJson(&dc, "[\"abc\"]");
        try testing.expectEqualStrings(fn_opt1_str_a.?, "abc");
        try testing.expectEqualStrings(res.result, "\"abc\"");
    }
}

test "Test rpc call on fn_opt1_cat with optional object argument." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var dc: DispatchCtx = .{
        .arena = arena_alloc,
        .logger = nop_logger.asLogger(),
    };
    var ctx = {};

    {
        var h = json_call.makeRpcHandler(&ctx, fn_opt1_cat);

        _ = try h.invokeJson(&dc, 
                \\{
                \\ "cat_name": "cat1",
                \\ "weight": 5.5,
                \\ "eye_color": "brown"
                \\}
        );
        try testing.expectEqualStrings(fn_opt1_cat_a.?.cat_name, "cat1");
        
        _ = try h.invoke(&dc, .{ .null = {} });
        try testing.expect(fn_opt1_cat_a == null);

        _ = try h.invokeJson(&dc, "");
        try testing.expect(fn_opt1_cat_a == null);

        var array0 = std.json.Array.init(alloc);
        defer array0.deinit();
        _ = try h.invoke(&dc, .{ .array = array0 });
        try testing.expect(fn_opt1_cat_a == null);
    }
}


const CalledCtx = struct {
    called: bool = false,
};

fn fn_dc_integer1(dc: *DispatchCtx, a: i64) ![]const u8 {
    zigjr.asPtr(ReqUserData, dc.user_data).x = a;
    return try allocPrint(dc.arena, "a is {}", .{a});
}

fn fn_ctx_dc_integer1(ctx: *CalledCtx, dc: *DispatchCtx, a: i64) ![]const u8 {
    zigjr.asPtr(ReqUserData, dc.user_data).x = a;
    ctx.called = true;
    return try allocPrint(dc.arena, "a is {}", .{a});
}

fn fn_alloc_integer1(arena: Allocator, a: i64) ![]const u8 {
    return try allocPrint(arena, "a is {}", .{a});
}


test "Test rpc call with DispatchCtx." {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena = ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    var nop_logger = zigjr.NopLogger{};
    var ctx = CalledCtx {};
    var userData = ReqUserData{};
    {
        var dc: DispatchCtx = .{
            .arena = arena_alloc,
            .logger = nop_logger.asLogger(),
            .user_data = &userData,
        };
        var h1 = json_call.makeRpcHandler(&ctx, fn_dc_integer1);
        const dr1 = try h1.invokeJson(&dc, "[123]");
        _=dr1;
        // std.debug.print("dr1.result: {s}\n", .{dr1.result});
        _ = try h1.invoke(&dc, .{ .integer = 123 });
        try testing.expect(userData.x == 123);

        var h2 = json_call.makeRpcHandler(&ctx, fn_alloc_integer1);
        const dr2 = try h2.invokeJson(&dc, "[123]");
        // std.debug.print("dr2.result: {s}\n", .{dr2.result});
        try testing.expectEqualStrings("\"a is 123\"", dr2.result);

        var h3 = json_call.makeRpcHandler(&ctx, fn_ctx_dc_integer1);
        ctx.called = false;
        _ = try h3.invokeJson(&dc, "[123]");
        // std.debug.print("dr3.result: {s}\n", .{dr3.result});
        try testing.expect(ctx.called);
    }
}

test "Test rpc call with missing DispatchCtx when registering a handler." {

    // Uncomment the following to test compile time check on the DispatchCtx type requirement.
    // var ctx = CalledCtx {};
    // _ = json_call.makeRpcHandler(&ctx, void, fn_alloc_integer1);
}


