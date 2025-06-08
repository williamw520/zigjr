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


fn fn1(a: i64) void {
    std.debug.print("fn1() called, a:{}\n", .{a});
}

fn fn1_with_err(a: i64) !void {
    std.debug.print("fn1_with_err() called, a:{}\n", .{a});
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

test "Test call on fn0." {
    const alloc = gpa.allocator();
    {
        var ctx = {};
        var h = try json_call.makeRpcHandler(&ctx, fn0, alloc);
        defer h.deinit();
        _ = try h.invoke(.{ .null = {} });
        h.invokeDone();
        _ = try h.invoke(.{ .null = {} });
        h.invokeDone();
        _ = try h.invoke(.{ .null = {} });
        h.invokeDone();
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}




