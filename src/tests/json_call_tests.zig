const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const StringHashMap = std.hash_map.StringHashMap;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const zigjr = @import("../zigjr.zig");
const json_call = @import("../rpc/json_call.zig");
const JrErrors = zigjr.JrErrors;



var gpa = std.heap.GeneralPurposeAllocator(.{}){};


fn fn0() void {
    std.debug.print("fn0() called\n", .{});
}

fn fn0_with_err() !void {
    std.debug.print("fn0_with_err() called\n", .{});
}

fn fn0_return_value() []const u8 {
    std.debug.print("fn0_return_value() called\n", .{});
    return "Hello";
}

fn fn0_return_value_with_err() ![]const u8 {
    std.debug.print("fn0_return_value_with_err() called\n", .{});
    return "Hello";
}

fn fn0_alloc(alloc: Allocator) !void {
    std.debug.print("fn0_alloc() called\n", .{});
    // The arena allocator will take care of freeing it.
    _ = try alloc.dupe(u8, "Hello. Allocate some memory without freeing.");
}


fn fn1_integer(a: i64) void {
    std.debug.print("fn1_integer() called, a:{}\n", .{a});
}

fn fn1_float(a: f64) void {
    std.debug.print("fn1_float() called, a:{}\n", .{a});
}

fn fn1_bool(a: bool) void {
    std.debug.print("fn1_bool() called, a:{}\n", .{a});
}

fn fn1_string(a: []const u8) void {
    std.debug.print("fn1_string() called, a:{s}\n", .{a});
}

fn fn1_with_err(a: i64) !void {
    std.debug.print("fn1_with_err() called, a:{}\n", .{a});
}

fn fn1_alloc_with_err(alloc: Allocator, a: i64) !void {
    std.debug.print("fn1_alloc_with_err() called, a:{}\n", .{a});
    // The arena allocator will take care of freeing it.
    _ = try alloc.dupe(u8, "Hello. Allocate some memory without freeing.");
}


fn fn4(a: i64, b: f64, c: bool, d: []const u8) void {
    std.debug.print("fn4_integer() called, a:{}, b:{}, c:{}, d:{s}\n", .{a, b, c, d});
}


const CatInfo = struct {
    cat_name: []const u8,
    weight: f64,
    eye_color: []const u8,
};

fn fn_cat(a: CatInfo) void {
    std.debug.print("fn4_integer() called, a:{any}\n", .{a});
}



test "Test rpc call on fn0." {
    const alloc = gpa.allocator();
    {
        var ctx = {};
        var h = try json_call.makeRpcHandler(&ctx, fn0, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .null = {} });
        _ = try h.invokeJson("");
        h.reset();
        _ = try h.invoke(.{ .null = {} });
        h.reset();
        _ = try h.invoke(.{ .null = {} });
        h.reset();
    }

    {
        var ctx = {};
        var h = try json_call.makeRpcHandler(&ctx, fn0_alloc, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .null = {} });
        _ = try h.invoke(.{ .null = {} });
        _ = try h.invokeJson("");
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
        _ = try h.invoke(.{ .integer = 123 });
        _ = try h.invokeJson("123");
        h.reset();

        var array = std.json.Array.init(alloc);
        try array.append(.{ .integer = 456 });
        defer array.deinit();
        _ = try h.invoke(.{ .array = array });
        _ = try h.invokeJson("[123]");
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_alloc_with_err, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .integer = 123 });
        _ = try h.invokeJson("123");
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
        _ = try h.invoke(.{ .array = array });
        _ = try h.invokeJson("[1.23]");
        h.reset();
    }
    
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_bool, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .bool = true });
        _ = try h.invokeJson("true");
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_bool, alloc);
        defer h.deinit();
        var array = std.json.Array.init(alloc);
        try array.append(.{ .bool = false });
        defer array.deinit();
        _ = try h.invoke(.{ .array = array });
        _ = try h.invokeJson("[false]");
        h.reset();
    }
    
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_string, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .string = "Hello123" });
        _ = try h.invokeJson("\"Hello123\"");
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_string, alloc);
        defer h.deinit();
        var array = std.json.Array.init(alloc);
        try array.append(.{ .string = "Hello456" });
        defer array.deinit();
        _ = try h.invoke(.{ .array = array });
        _ = try h.invokeJson("[\"Hello456\"]");
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
        h.reset();
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}




