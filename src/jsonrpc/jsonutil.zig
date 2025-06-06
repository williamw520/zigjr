// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;
const Value = std.json.Value;

const errors = @import("errors.zig");
const JrErrors = errors.JrErrors;


/// Convert the std.json.Value to the primitive type (bool, i64, f64, []const u8),
/// within the scope of JSON data type.
pub fn ValueAs(comptime V: type) type {
    const vinfo = @typeInfo(V);

    // Check for supported parameter value types.
    switch (vinfo) {
        .bool => {},
        .int => {
            if (vinfo.int.signedness == .unsigned) @compileError("Required signed integer, at least i64.");
            if (vinfo.int.bits < 64) @compileError("Required at least i64 for integer.");
        },
        .float => {
            if (vinfo.float.bits < 64) @compileError("Required at least f64 for floating point number.");
        },
        .pointer => {
            if (vinfo.pointer.child != u8)
                @compileError("String slice requires the '[]const u8' type.");
        },
        else => @compileError("Unsupported parameter value type."),
    }

    return struct {
        pub fn from(json_value: Value) !V {
            return fromAlloc(json_value, .{});
        }

        pub fn fromAlloc(json_value: Value, opts: struct { alloc: ?Allocator = null }) !V {
            switch (vinfo) {
                .bool => switch (json_value) {
                    .bool       => |x| return x,
                    .integer    => |x| return x != 0,
                    .float      => |x| return x != 0.0,
                    .string     => |x| return std.mem.eql(u8, x, "true"),
                    else        => return JrErrors.InvalidJsonValueType,
                },
                .int => switch (json_value) {
                    .integer    => |x| return x,
                    .string     => |x| return try std.fmt.parseInt(i64, x, 10),
                    else        => return JrErrors.InvalidJsonValueType,
                },
                .float => switch (json_value) {
                    .float      => |x| return x,
                    .integer    => |x| return @as(f64, @floatFromInt(x)),
                    .string     => |x| return try std.fmt.parseFloat(f64, x),
                    else        => return JrErrors.InvalidJsonValueType,
                },
                .pointer => {
                    if (opts.alloc) |alloc| {
                        switch (json_value) {
                            .bool       => |x| return try allocPrint(alloc, "{}", .{x}),
                            .integer    => |x| return try allocPrint(alloc, "{}", .{x}),
                            .float      => |x| return try allocPrint(alloc, "{}", .{x}),
                            .string     => |x| return try allocPrint(alloc, "{s}", .{x}),
                            else        => return JrErrors.InvalidJsonValueType,
                        }
                    } else {
                        switch (json_value) {
                            .string     => |x| return x,
                            else        => return JrErrors.InvalidJsonValueType,
                        }
                    }
                },
                else => return JrErrors.InvalidParamType,
            }
        }
        
    };

}


