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


test "Test simple JSON value conversion." {
    const alloc = gpa.allocator();
    {
        _=alloc;
        try testing.expectEqual(json_call.ValueAs(i64).from(.{ .integer = 10 }), 10);
        try testing.expectEqual(json_call.ValueAs(i128).from(.{ .integer = 10 }), 10);

        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .bool = true }), true);
        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .bool = false }), false);
        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .integer = 0 }), false);
        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .integer = 1 }), true);
        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .integer = 2 }), true);
        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .integer = -2 }), true);
        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .float = 0 }), false);
        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .float = 1 }), true);
        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .float = -1 }), true);
        try testing.expectEqual(json_call.ValueAs(bool).from(.{ .float = -1.2 }), true);

        try testing.expectEqual(json_call.ValueAs(f64).from(.{ .float = 1.2 }), 1.2);
        try testing.expectEqual(json_call.ValueAs(f64).from(.{ .float = -1.2 }), -1.2);
        try testing.expectEqual(json_call.ValueAs(f128).from(.{ .float = 10 }), 10);
        try testing.expectEqual(json_call.ValueAs(f64).from(.{ .integer = 12 }), 12);

        try testing.expectEqualSlices(u8, try json_call.ValueAs([]const u8).from(.{ .string = "hello" }), "hello");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test simple JSON value conversion on invalid JSON values." {
    const alloc = gpa.allocator();
    {
        _=alloc;
        try testing.expectEqual(json_call.ValueAs(i64).from(.{ .float = 0 }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(json_call.ValueAs(i128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(json_call.ValueAs(i64).from(.{ .string = "abc" }), error.InvalidCharacter);

        try testing.expectEqual(json_call.ValueAs(f128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(json_call.ValueAs(f64).from(.{ .string = "abc" }), error.InvalidCharacter);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test JSON value conversion with alloc." {
    const alloc = gpa.allocator();
    {
        const x = try json_call.ValueAs([]const u8).fromAlloc(.{ .string = "hello" }, .{ .alloc = alloc });
        try testing.expectEqualSlices(u8, x, "hello");

        try testing.expectEqual(json_call.ValueAs(i64).fromAlloc(.{ .integer = 10 }, .{ .alloc = alloc }), 10);
        
        alloc.free(x);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test rpc call on fn0." {
    const alloc = gpa.allocator();
    {
        var ctx = {};
        var h = try json_call.makeRpcHandler(&ctx, fn0, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .null = {} });
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
        h.reset();

        var array = std.json.Array.init(alloc);
        try array.append(.{ .integer = 456 });
        defer array.deinit();
        _ = try h.invoke(.{ .array = array });
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_alloc_with_err, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .integer = 123 });
    }

    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_float, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .float = 1.23 });
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_float, alloc);
        defer h.deinit();
        var array = std.json.Array.init(alloc);
        try array.append(.{ .float = 4.56 });
        defer array.deinit();
        _ = try h.invoke(.{ .array = array });
        h.reset();
    }
    
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_bool, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .bool = true });
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_bool, alloc);
        defer h.deinit();
        var array = std.json.Array.init(alloc);
        try array.append(.{ .bool = false });
        defer array.deinit();
        _ = try h.invoke(.{ .array = array });
        h.reset();
    }
    
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_string, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .string = "Hello123" });
        h.reset();
    }
    {
        var h = try json_call.makeRpcHandler(&ctx, fn1_string, alloc);
        defer h.deinit();
        var array = std.json.Array.init(alloc);
        try array.append(.{ .string = "Hello456" });
        defer array.deinit();
        _ = try h.invoke(.{ .array = array });
        h.reset();
    }

    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}




