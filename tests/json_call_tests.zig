const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const StringHashMap = std.hash_map.StringHashMap;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;

const zigjr = @import("zigjr");
const json_call = zigjr.json_call;


var gpa = std.heap.GeneralPurposeAllocator(.{}){};


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



test "Test rpc call on fn0." {
    const alloc = gpa.allocator();
    {
        var ctx = {};
        var h = try json_call.makeRpcHandler(&ctx, fn0, alloc);
        defer h.deinit();
        fn0_called = false;
        _ = try h.invoke(.{ .null = {} });
        try testing.expect(fn0_called);
        fn0_called = false;

        _ = try h.invokeJson("");
        h.reset();
        try testing.expect(fn0_called);
        fn0_called = false;

        _ = try h.invoke(.{ .null = {} });
        h.reset();
        try testing.expect(fn0_called);
        fn0_called = false;

        _ = try h.invoke(.{ .null = {} });
        h.reset();
        try testing.expect(fn0_called);
        fn0_called = false;
    }

    {
        var ctx = {};
        var h = try json_call.makeRpcHandler(&ctx, fn0_with_err, alloc);
        defer h.deinit();
        fn0_with_err_called = false;

        _ = try h.invoke(.{ .null = {} });
        try testing.expect(fn0_with_err_called);
        fn0_with_err_called = false;

        _ = try h.invoke(.{ .null = {} });
        try testing.expect(fn0_with_err_called);
        fn0_with_err_called = false;

        _ = try h.invokeJson("");
        try testing.expect(fn0_with_err_called);
        fn0_with_err_called = false;

        const dresult = try h.invoke(.{ .null = {} });
        try testing.expect(fn0_with_err_called);
        fn0_with_err_called = false;
        try testing.expect(dresult == .none);
        h.reset();
    }


    {
        var ctx = {};
        var h = try json_call.makeRpcHandler(&ctx, fn0_return_json_str, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .null = {} });
        _ = try h.invoke(.{ .null = {} });
        _ = try h.invokeJson("");
        const dresult = try h.invoke(.{ .null = {} });
        // std.debug.print("result {s}\n", .{dresult.result});
        try testing.expectEqualSlices(u8, dresult.result, "{ \"foobar\": 42 }");
        h.reset();
    }

    {
        var ctx = {};
        var h = try json_call.makeRpcHandler(&ctx, fn0_alloc, alloc);
        defer h.deinit();
        fn0_alloc_called = false;

        _ = try h.invoke(.{ .null = {} });
        try testing.expect(fn0_alloc_called);
        fn0_alloc_called = false;

        _ = try h.invoke(.{ .null = {} });
        try testing.expect(fn0_alloc_called);
        fn0_alloc_called = false;

        _ = try h.invokeJson("");
        try testing.expect(fn0_alloc_called);
        fn0_alloc_called = false;
        h.reset();
    }

    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


test "Test rpc call on fn1." {
    const alloc = gpa.allocator();
    var ctx = {};
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_integer, alloc);
        defer h.deinit();
        fn1_integer_called = false;

        _ = try h.invoke(.{ .integer = 123 });
        try testing.expect(fn1_integer_called);
        fn1_integer_called = false;

        _ = try h.invokeJson("123");
        h.reset();
        try testing.expect(fn1_integer_called);
        fn1_integer_called = false;

        var array = std.json.Array.init(alloc);
        try array.append(.{ .integer = 456 });
        defer array.deinit();
        _ = try h.invoke(.{ .array = array });
        try testing.expect(fn1_integer_called);
        fn1_integer_called = false;

        _ = try h.invokeJson("[123]");
        h.reset();
        try testing.expect(fn1_integer_called);
        fn1_integer_called = false;
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_alloc_with_err, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .integer = 123 });
        try testing.expect(fn1_alloc_with_err_called);
        fn1_alloc_with_err_called = false;

        _ = try h.invokeJson("123");
        try testing.expect(fn1_alloc_with_err_called);
    }

    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_float, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .float = 1.23 });
        _ = try h.invokeJson("1.23");
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_float, alloc);
        defer h.deinit();
        var array = std.json.Array.init(alloc);
        try array.append(.{ .float = 4.56 });
        defer array.deinit();
        fn1_float_called = false;
        
        _ = try h.invoke(.{ .array = array });
        try testing.expect(fn1_float_called);
        fn1_float_called = false;
        
        _ = try h.invokeJson("[1.23]");
        try testing.expect(fn1_float_called);
        fn1_float_called = false;
        h.reset();
    }
    
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_bool, alloc);
        defer h.deinit();
        fn1_bool_called = false;

        _ = try h.invoke(.{ .bool = true });
        try testing.expect(fn1_bool_called);
        fn1_bool_called = false;
        
        _ = try h.invokeJson("true");
        try testing.expect(fn1_bool_called);
        fn1_bool_called = false;
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_bool, alloc);
        defer h.deinit();
        var array = std.json.Array.init(alloc);
        try array.append(.{ .bool = false });
        defer array.deinit();
        fn1_bool_called = false;

        _ = try h.invoke(.{ .array = array });
        try testing.expect(fn1_bool_called);
        fn1_bool_called = false;
        
        _ = try h.invokeJson("[false]");
        try testing.expect(fn1_bool_called);
        fn1_bool_called = false;
        
        h.reset();
    }
    
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_string, alloc);
        defer h.deinit();
        fn1_string_called = false;

        _ = try h.invoke(.{ .string = "Hello123" });
        try testing.expect(fn1_string_called);
        fn1_string_called = false;

        _ = try h.invokeJson("\"Hello123\"");
        try testing.expect(fn1_string_called);
        fn1_string_called = false;
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_string, alloc);
        defer h.deinit();
        var array = std.json.Array.init(alloc);
        try array.append(.{ .string = "Hello456" });
        defer array.deinit();
        fn1_string_called = false;
        
        _ = try h.invoke(.{ .array = array });
        try testing.expect(fn1_string_called);
        fn1_string_called = false;
        
        _ = try h.invokeJson("[\"Hello456\"]");
        try testing.expect(fn1_string_called);
        fn1_string_called = false;
        
        h.reset();
    }

    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test rpc call on fn4." {
    const alloc = gpa.allocator();
    var ctx = {};
    {
        var h = try json_call.makeRpcHandler(&ctx, fn4, alloc);
        defer h.deinit();
        _ = try h.invokeJson("[123, 4.56, true, \"abc\"]");
        try testing.expect(fn4_called);
        h.reset();
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test rpc call on fn_cat." {
    const alloc = gpa.allocator();
    var ctx = {};
    {
        var h = try json_call.makeRpcHandler(&ctx, fn_cat, alloc);
        defer h.deinit();
        _ = try h.invokeJson(
                \\{
                \\ "cat_name": "cat1",
                \\ "weight": 5.5,
                \\ "eye_color": "brown"
                \\}
        );
        try testing.expect(fn_cat_called);
        h.reset();
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}




