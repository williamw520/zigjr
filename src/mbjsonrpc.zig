// Toposort
// A Zig library for performing topological sort.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const indexOfScalar = std.mem.indexOfScalar;
const StringHashMap = std.hash_map.StringHashMap;
const AutoHashMap = std.hash_map.AutoHashMap;
const allocPrint = std.fmt.allocPrint;
const parseInt = std.fmt.parseInt;
const tokenizeScalar = std.mem.tokenizeScalar;
const Scanner = std.json.Scanner;
const ParseOptions = std.json.ParseOptions;
const innerParse = std.json.innerParse;
const ParseFromValueError = std.json.ParseFromValueError;


const ErrorCode = enum(i32) {
    None = 0,
    ParseError = -32700,        // Invalid JSON was received by the server.
    InvalidRequest = -32600,    // The JSON sent is not a valid Request object.
    MethodNotFound = -32601,    // The method does not exist / is not available.
    InvalidParams = -32602,     // Invalid method parameter(s).
    InternalError = -32603,     // Internal JSON-RPC error.
    ServerError = -32000,       // -32000 to -32099 reserved for implementation defined errors.
};

const RequestError = struct {
    code:   ErrorCode = .None,
    msg:    []const u8 = "",
};

const IdType = union(enum) {
    num:    i64,
    str:    []const u8,

    // Custom parsing when the JSON parser encounters a field of the IdType type.
    pub fn jsonParse(allocator: Allocator, source: *Scanner, options: ParseOptions) !IdType {
        // std.debug.print("jsonParse: {any}\n", .{source.peekNextTokenType()});
        return switch (try source.peekNextTokenType()) {
            .number => .{ .num = try innerParse(i64, allocator, source, options) },
            .string => .{ .str = try innerParse([]const u8, allocator, source, options) },
            else => error.InvalidCharacter,
        };
    }
};

const RequestBody = struct {
    jsonrpc:        [3]u8,
    method:         []u8,
    params:         std.json.Value,
    id:             ?IdType = null,
};

/// Handle an incoming JSON-RPC 2.0 request message.
pub const Request = struct {
    const Self = @This();

    err:            RequestError,
    body:           ?RequestBody = null,
    _parsed_json:   ?std.json.Parsed(RequestBody) = null,

    pub fn init(allocator: Allocator, message: []const u8) !Self {
        // std.debug.print("msg: {s}\n", .{msg});
        const parsed = std.json.parseFromSlice(RequestBody, allocator, message, .{}) catch |err|
            switch (err) {
                ParseFromValueError.MissingField,
                ParseFromValueError.UnknownField,
                ParseFromValueError.DuplicateField => {
                    return .{ .err = .{ .code = ErrorCode.InvalidRequest,
                                        .msg = @errorName(err) } };
                },
                error.OutOfMemory,
                error.BufferUnderrun => {
                    return .{ .err = .{ .code = ErrorCode.InternalError,
                                        .msg = @errorName(err) } };
                },
                else => {
                    return .{ .err = .{ .code = ErrorCode.ParseError,
                                        .msg = @errorName(err) } };
                },
        };
        // TODO: validate method and params in parsed.
        return .{ .body = parsed.value, ._parsed_json = parsed, .err = RequestError{} };
    }

    pub fn deinit(self: *const Self) void {
        if (self._parsed_json) |parsed| parsed.deinit();
    }

    pub fn has_error(self: Self) bool {
        return self.err.code != .None;
    }

    /// Build a Response message, or an Error message if there was a parse error.
    /// Caller needs to call allocator.free() on the returned message free the memory.
    pub fn response(self: Self, allocator: Allocator, result: []const u8) ![]const u8 {
        if (self.body) |body| {
            if (body.id) |id| {
                return response_with_id(allocator, result, id);
            } else {
                return response_without_id(allocator, result);
            }
        } else {
            return self.response_error(allocator);
        }
    }

    /// Build an Error message.
    /// Caller needs to call allocator.free() on the returned message free the memory.
    pub fn response_error(self: Self, allocator: Allocator) ![]const u8 {
        if (self.body) |body| {
            if (body.id) |id| {
                return response_error_with_id(allocator, self.err, id);
            }
        }
        return response_error_without_id(allocator, self.err);
    }
    
};

fn response_with_id(allocator: Allocator, result: []const u8, id: IdType) ![]const u8 {
    return switch (id) {
        .num => try allocPrint(allocator,
                    \\{{ "jsonrpc": "2.0", "result": {s}, "id": {} }}
                    , .{result, id.num}),
        .str => try allocPrint(allocator,
                    \\{{ "jsonrpc": "2.0", "result": {s}, "id": "{s}" }}
                    , .{result, id.str}),
    };
}

fn response_without_id(allocator: Allocator, result: []const u8) ![]const u8 {
    return try allocPrint(allocator,
                    \\{{ "jsonrpc": "2.0", "result": {s}, "id": null }}
                    , .{result});
}

fn response_error_with_id(allocator: Allocator, err: RequestError, id: IdType) ![]const u8 {
    return switch (id) {
        .num => try allocPrint(allocator,
                    \\{{ "jsonrpc": "2.0", "error": {}, "message": {s}, "id": {} }}
                    , .{@intFromEnum(err.code), err.msg, id.num}),
        .str => try allocPrint(allocator,
                    \\{{ "jsonrpc": "2.0", "error": {}, "message": {s}, "id": "{s}" }}
                    , .{@intFromEnum(err.code), err.msg, id.str}),
    };
}

fn response_error_without_id(allocator: Allocator, err: RequestError) ![]const u8 {
    return try allocPrint(allocator,
                    \\{{ "jsonrpc": "2.0", error": {{ code: {}, message: "{s}" }}, "id": null }}
                    , .{@intFromEnum(err.code), err.msg});
}

test {
    std.debug.print("test...\n", .{});
    
}

