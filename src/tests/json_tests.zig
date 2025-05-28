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


fn foo(a: i64, b: bool) void { std.debug.print("foo: a={}, b={}\n", .{a, b}); }
fn bar(a: f64) void { std.debug.print("bar: a={}\n", .{a}); }
fn baz(a: []const u8, b: i64, c: bool) void { std.debug.print("baz: a={s}, b={}, c={}\n", .{a, b, c}); }

test "Test calling function with with JSON Values." {
    const alloc = gpa.allocator();
    {
        const param_tt = jsonutil.ParamTupleType(foo);
        var args = Array.init(alloc);
        defer args.deinit();
        try args.append(.{ .integer = 1 });
        try args.append(.{ .bool = true });
        const param_tuple = try jsonutil.valuesToTuple(param_tt, args);
        @call(.auto, foo, param_tuple);
    }
    {
        const param_tt = jsonutil.ParamTupleType(bar);
        var args = Array.init(alloc);
        defer args.deinit();
        try args.append(.{ .float = 1.11 });
        const param_tuple = try jsonutil.valuesToTuple(param_tt, args);
        @call(.auto, bar, param_tuple);
    }
    {
        const param_tt = jsonutil.ParamTupleType(baz);
        var args = Array.init(alloc);
        defer args.deinit();
        try args.append(.{ .string = "hello" });
        try args.append(.{ .integer = 4 });
        try args.append(.{ .bool = true });
        const param_tuple = try jsonutil.valuesToTuple(param_tt, args);
        @call(.auto, baz, param_tuple);
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}




test "Test calling function with 2 params." {
    const alloc = gpa.allocator();
    {
        _=alloc;
        const result = try jsonutil.Fn2(f64, bool, struct {
            pub fn run(p1: f64, p2: bool) ![]const u8 {
                std.debug.print("p1={}, p2={}\n", .{p1, p2});
                return "done";
            }
        }).callWith(.{ .float = 10 }, .{ .bool = true });
        std.debug.print("result={s}\n", .{result});
    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
}



