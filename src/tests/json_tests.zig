const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const zigjr = @import("../zigjr.zig");
const jsonutil = @import("../jsonrpc/jsonutil.zig");
const JrErrors = zigjr.JrErrors;



var gpa = std.heap.GeneralPurposeAllocator(.{}){};


test "Test simple JSON value conversion." {
    const alloc = gpa.allocator();
    {
        _=alloc;
        try testing.expectEqual(jsonutil.ValueAs(i64).from(.{ .integer = 10 }), 10);
        try testing.expectEqual(jsonutil.ValueAs(i128).from(.{ .integer = 10 }), 10);

        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .bool = true }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .bool = false }), false);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .integer = 0 }), false);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .integer = 1 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .integer = 2 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .integer = -2 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .float = 0 }), false);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .float = 1 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .float = -1 }), true);
        try testing.expectEqual(jsonutil.ValueAs(bool).from(.{ .float = -1.2 }), true);

        try testing.expectEqual(jsonutil.ValueAs(f64).from(.{ .float = 1.2 }), 1.2);
        try testing.expectEqual(jsonutil.ValueAs(f64).from(.{ .float = -1.2 }), -1.2);
        try testing.expectEqual(jsonutil.ValueAs(f128).from(.{ .float = 10 }), 10);
        try testing.expectEqual(jsonutil.ValueAs(f64).from(.{ .integer = 12 }), 12);

        try testing.expectEqualSlices(u8, try jsonutil.ValueAs([]const u8).from(.{ .string = "hello" }), "hello");
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test simple JSON value conversion on invalid JSON values." {
    const alloc = gpa.allocator();
    {
        _=alloc;
        try testing.expectEqual(jsonutil.ValueAs(i64).from(.{ .float = 0 }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(jsonutil.ValueAs(i128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(jsonutil.ValueAs(i64).from(.{ .string = "abc" }), error.InvalidCharacter);

        try testing.expectEqual(jsonutil.ValueAs(f128).from(.{ .bool = true }), JrErrors.InvalidJsonValueType);
        try testing.expectEqual(jsonutil.ValueAs(f64).from(.{ .string = "abc" }), error.InvalidCharacter);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}

test "Test JSON value conversion with alloc." {
    const alloc = gpa.allocator();
    {
        const x = try jsonutil.ValueAs([]const u8).fromAlloc(.{ .string = "hello" }, .{ .alloc = alloc });
        try testing.expectEqualSlices(u8, x, "hello");

        try testing.expectEqual(jsonutil.ValueAs(i64).fromAlloc(.{ .integer = 10 }, .{ .alloc = alloc }), 10);
        
        alloc.free(x);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}


