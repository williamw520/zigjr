const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;
const allocPrint = std.fmt.allocPrint;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const nanoTimestamp = std.time.nanoTimestamp;
const Value = std.json.Value;
const Array = std.json.Array;


var gpa = std.heap.GeneralPurposeAllocator(.{}){};


fn foo(a: u8, b: i32) void { std.debug.print("foo: a={}, b={}\n", .{a, b}); }
fn bar(a: f64) void { std.debug.print("bar: a={}\n", .{a}); }

fn ofFn(comptime func: anytype) void {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    //std.debug.print("fn_info={any}\n", .{fn_info.params});
    inline for (fn_info.params, 0..)|param, i| {
        std.debug.print("arg_{d}: param={any}\n", .{i, param});
        // std.fmt.comptimePrint("arg_{d}: type={any}", .{i, param.type});
    }
}

fn paramsAsTuple(comptime func: anytype) type {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";

    comptime var fields: [fn_info.params.len]std.builtin.Type.StructField = undefined;
    inline for (fn_info.params, 0..)|param, i| {
        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = param.type orelse null,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..],
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

fn makeTuple(comptime tuple_type: type) tuple_type {
    const tt_info = @typeInfo(tuple_type).@"struct";
    var tuple: tuple_type = undefined;
    inline for (tt_info.fields, 0..)|field, i| {
        std.debug.print("@\"{d}\": {any}\n", .{i, field});
        @field(tuple, field.name) = 42;
    }
    return tuple;
}

fn jsonToTuple(comptime tuple_type: type, args: Array) tuple_type {
    const tt_info = @typeInfo(tuple_type).@"struct";
    var tuple: tuple_type = undefined;
    inline for (tt_info.fields, 0..)|field, i| {
        const arg = args.items[i];
        std.debug.print("@\"{d}\"| field: {any} | arg: {any}\n", .{i, field, arg});
        @field(tuple, field.name) = 42;
        switch (field.type) {
            bool => {
                @field(tuple, field.name) = arg.bool;
            },
            u8 => {
                @field(tuple, field.name) = @as(u8, @intCast(arg.integer));
            },
            i32 => {
                @field(tuple, field.name) = @as(i32, @intCast(arg.integer));
            },
            f64 => {
                @field(tuple, field.name) = arg.float;
            },
            else => {}
        }
    }
    return tuple;
}

test "Misc" {
    const alloc = gpa.allocator();
    {
        var s1 = struct {
            a: u8 = 'A',
            b: i32 = 1,
        }{};
        std.debug.print("s1={any}\n", .{s1});
        @field(s1, "b") = 10;
        std.debug.print("s1={any}\n", .{s1});

        const t1 = .{ 'A', 1 };
        std.debug.print("t1={any}\n", .{t1});

        foo('A', 2);
        bar(1.1);

        ofFn(foo);
        ofFn(bar);

        const foo_type1 = paramsAsTuple(foo);
        std.debug.print("foo_type1={any}\n", .{foo_type1});
        const foo_value1: foo_type1 = .{ 'B', 2 };
        std.debug.print("foo_value1={any}\n", .{foo_value1});

        const bar_type1 = paramsAsTuple(bar);
        std.debug.print("bar_type1={any}\n", .{bar_type1});
        var bar_value1: bar_type1 = .{ 2.2 };
        std.debug.print("bar_value1={any}\n", .{bar_value1});
        bar_value1.@"0" = 3.3;
        std.debug.print("bar_value1={any}\n", .{bar_value1});

        const tt1 = makeTuple(foo_type1);
        std.debug.print("tt1={any}\n", .{tt1});

        var args1 = Array.init(alloc);
        defer args1.deinit();
        try args1.append(.{ .integer = 4 });
        try args1.append(.{ .integer = 40 });
        const tt2 = jsonToTuple(foo_type1, args1);
        std.debug.print("tt2={any}\n", .{tt2});

        var bar_args2 = Array.init(alloc);
        defer bar_args2.deinit();
        try bar_args2.append(.{ .float = 4.4 });
        const bb1 = jsonToTuple(bar_type1, bar_args2);
        std.debug.print("bb1={any}\n", .{bb1});

    }
    if (gpa.detectLeaks()) std.debug.print("Memory leak detected!\n", .{});
        
}

