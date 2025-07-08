// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const Parsed = std.json.Parsed;
const Scanner = std.json.Scanner;
const ParseOptions = std.json.ParseOptions;
const innerParse = std.json.innerParse;
const ParseError = std.json.ParseError;
const Value = std.json.Value;
const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;

const errors = @import("errors.zig");
const ErrorCode = errors.ErrorCode;
const JrErrors = errors.JrErrors;

const req = @import("request.zig");
const res = @import("response.zig");



pub fn parseRpcMessage(alloc: Allocator, json_str: []const u8) RpcMessageResult {
    if (std.mem.indexOf(u8, json_str, "\"method\":")) |_| {
        const req_result = req.parseRpcRequest(alloc, json_str);
        if (!req_result.isMissingMethod()) {
            return .{ .request_result = req_result };   // a valid request or a non-missing-method error.
        }
    }
    return .{ .response_result = res.parseRpcResponse(alloc, json_str) };
}

pub const RpcMessageResult = union(enum) {
    request_result:     req.RpcRequestResult,
    response_result:    res.RpcResponseResult,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .request_result     => |*rr| rr.deinit(),
            .response_result    => |*rr| rr.deinit(),
        }
    }
};

