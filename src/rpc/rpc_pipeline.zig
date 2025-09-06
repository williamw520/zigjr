// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;
const ArrayList = std.ArrayList;

const zigjr = @import("../zigjr.zig");

const parseRpcRequest = zigjr.parseRpcRequest;
const RpcRequest = zigjr.RpcRequest;
const RpcId = zigjr.RpcId;
const RpcRequestResult = zigjr.RpcRequestResult;

const parseRpcResponse = zigjr.parseRpcResponse;
const parseRpcResponseOwned = zigjr.parseRpcResponseOwned;
const RpcResponse = zigjr.RpcResponse;
const RpcResponseResult = zigjr.RpcResponseResult;
const RpcResponseMessage = zigjr.RpcResponseMessage;

const parseRpcMessage = zigjr.parseRpcMessage;
const RpcMessageResult = zigjr.RpcMessageResult;

const ErrorCode = zigjr.errors.ErrorCode;
const JrErrors = zigjr.errors.JrErrors;
const AllocError = zigjr.errors.AllocError;

const composer = zigjr.composer;

const RequestDispatcher = @import ("dispatcher.zig").RequestDispatcher;
const ResponseDispatcher = @import ("dispatcher.zig").ResponseDispatcher;
const DispatchResult = @import ("dispatcher.zig").DispatchResult;
var nopLogger = zigjr.NopLogger{};


pub const RequestPipeline = struct {
    req_dispatcher: RequestDispatcher,
    logger:         zigjr.Logger,

    pub fn init(req_dispatcher: RequestDispatcher, logger: ?zigjr.Logger) @This() {
        const l = logger orelse zigjr.Logger.implBy(&nopLogger);
        l.start("[RequestPipeline] Logging starts");
        return .{
            .req_dispatcher = req_dispatcher,
            .logger = l,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.logger.stop("[RequestPipeline] Logging stops");
    }

    /// Parse the JSON-RPC request message, run the dispatcher on request(s), 
    /// and write the JSON-RPC response(s) to the response_buf.
    /// The JSON request message can contain a single request or a batch of requests.
    /// Error is turned into a JSON-RPC error response message.
    /// The function returns a boolean flag indicating whether any response has been written,
    /// as notification requests have no response.
    pub fn runRequest(self: @This(), alloc: Allocator,
                      request_json: []const u8, response_buf: *ArrayList(u8),
                      headers: ?std.StringHashMap([]const u8)) AllocError!bool {
        _=headers;  // frame-level headers. May have character encoding. See FrameBuf.headers in frame.zig.

        self.logger.log("runRequest", "request_json ", request_json);
        var parsed_request = parseRpcRequest(alloc, request_json);
        defer parsed_request.deinit();
        const writer = response_buf.writer(alloc);
        const response_written = switch (parsed_request.request_msg) {
            .batch   => |reqs| try processRpcBatch(alloc,  reqs, self.req_dispatcher, writer),
            .request => |req|  try processRpcRequest(alloc, req, self.req_dispatcher, "", writer),
        };
        self.logger.log("runRequestResult", "response_json", response_buf.items);
        return response_written;
    }

    /// Run the request and return the response(s) as a JSON string. Same as runRequest().
    pub fn runRequestToJson(self: @This(), alloc: Allocator,
                            request_json: []const u8) AllocError!?[]const u8 {
        var response_buf: ArrayList(u8) = .empty;
        if (try self.runRequest(alloc, request_json, &response_buf, null)) {
            return try response_buf.toOwnedSlice(alloc);
        } else {
            response_buf.deinit(alloc);
            return null;
        }
    }

    /// Run the request and return the response(s) in a RpcResponseResult. Same as runRequest().
    /// This is mainly for testing.
    pub fn runRequestToResponse(self: @This(), alloc: Allocator,
                                request_json: []const u8) !RpcResponseResult {
        const response_json = try self.runRequestToJson(alloc, request_json);
        if (response_json) |json| {
            return parseRpcResponseOwned(alloc, json);  // response_json needs freeing.
        } else {
            return .{};
        }        
    }
};

fn processRpcBatch(alloc: Allocator, reqs: []RpcRequest, dispatcher: RequestDispatcher,
                writer: anytype) AllocError!bool {
    var has_output: bool = false;
    try writer.writeAll("[");
    for (reqs) |req| {
        const delimiter = if (has_output) ", " else "";
        if (try processRpcRequest(alloc, req, dispatcher, delimiter, writer)) {
            has_output = true;
        }
    }
    try writer.writeAll("]");
    return true;                    // batch always has some output like "[]".
}

/// Handle request's error, dispatch the request, and write the response.
/// Returns true if a response message is written, false for not as notification has no response.
fn processRpcRequest(alloc: Allocator, req: RpcRequest, req_dispatcher: RequestDispatcher,
                     delimiter: []const u8, writer: anytype) AllocError!bool {
    if (try handleRequestError(req, writer)) return true;
    errdefer req_dispatcher.dispatchEnd(alloc, req, DispatchResult.asNone());   // for AllocError
    const dresult = try dispatchRequest(alloc, req, req_dispatcher);
    const written = try writeResponse(dresult, req, delimiter, writer);
    req_dispatcher.dispatchEnd(alloc, req, dresult);
    return written;
}

fn handleRequestError(req: RpcRequest, writer: anytype) AllocError!bool {
    if (req.hasError()) {   // request has parsing or validation error.
        try composer.writeErrorResponseJson(req.id, req.err().code, req.err().err_msg, writer);
        return true;
    }
    return false;
}

fn dispatchRequest(alloc: Allocator, req: RpcRequest,
                  req_dispatcher: RequestDispatcher) AllocError!DispatchResult {
    return req_dispatcher.dispatch(alloc, req) catch |err| {
        // Turn dispatching error into DispatchResult.err.
        // Handle errors here so dispatchers don't have to worry about error handling.
        return DispatchResult.withAnyErr(err);
    };
}

fn writeResponse(dresult: DispatchResult, req: RpcRequest, delimiter: []const u8, writer: anytype) AllocError!bool {
    switch (dresult) {
        .none => {
            return false;       // notification request has no response written.
        },
        .result => |json| {
            if (req.id.isNotification()) {
                return false;   // notification request has no response written.
            }
            try writer.writeAll(delimiter);
            try composer.writeResponseJson(req.id, json, writer);
            return true;
        },
        .err => |err| {
            try writer.writeAll(delimiter);
            if (err.data)|data_json| {
                try composer.writeErrorDataResponseJson(req.id, err.code, err.msg, data_json, writer);
            } else {
                try composer.writeErrorResponseJson(req.id, err.code, err.msg, writer);
            }
            return true;
        },
    }
}


pub const ResponsePipeline = struct {
    alloc:          Allocator,
    res_dispatcher: ResponseDispatcher,

    pub fn init(alloc: Allocator, res_dispatcher: ResponseDispatcher) @This() {
        return .{
            .alloc = alloc,
            .res_dispatcher = res_dispatcher,
        };
    }

    /// Parse the JSON response message and run the dispatcher on RpcResponse(s).
    /// The JSON response message can contain a single response or a batch of responses.
    /// The 'anytype' dispatcher needs to have a dispatch() method with !void return type.
    /// Any parse error is returned to the caller and the dispatcher is not called.
    /// Any error coming from the dispatcher is passed back to caller.
    /// For batch responses, the first error from the dispatcher stops the processing.
    pub fn runResponse(self: @This(), response_json: []const u8,
                       headers: ?std.StringHashMap([]const u8)) !void {
        _=headers;  // frame-level headers. May have character encoding. See FrameBuf.headers in frame.zig.

        var response_result: RpcResponseResult = parseRpcResponse(self.alloc, response_json);
        defer response_result.deinit();
        try processResponseResult(self.alloc, response_result, self.res_dispatcher);
    }

};

fn processResponseResult(alloc: Allocator, response_result: RpcResponseResult,
                         dispatcher: ResponseDispatcher) anyerror!void {
    // Any errors (parsing or others) are forwarded to the handlers via the dispatcher.
    return switch (response_result.response_msg) {
        .response   => |rpc_response|  try dispatcher.dispatch(alloc, rpc_response),
        .batch      => |rpc_responses| for (rpc_responses) |rpc_response| {
            try dispatcher.dispatch(alloc, rpc_response);
        },
        .none       => {},
    };
}


pub const MessagePipeline = struct {
    req_dispatcher: RequestDispatcher,
    res_dispatcher: ResponseDispatcher,
    logger:         zigjr.Logger,

    pub fn init(req_dispatcher: RequestDispatcher, res_dispatcher: ResponseDispatcher,
                logger: ?zigjr.Logger) @This() {
        const l = logger orelse zigjr.Logger.implBy(&nopLogger);
        l.start("[MessagePipeline] Logging starts");
        return .{
            .logger = l,
            .req_dispatcher = req_dispatcher,
            .res_dispatcher = res_dispatcher,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.logger.stop("[MessagePipeline] Logging stops");
    }

    pub fn runMessage(self: @This(), alloc: Allocator,
                      message_json: []const u8, req_response_buf: *ArrayList(u8),
                      headers: ?std.StringHashMap([]const u8)) anyerror!MessageRunResult {
        _=headers;  // frame-level headers. May have character encoding. See FrameBuf.headers in frame.zig.

        self.logger.log("runMessage", "message_json ", message_json);
        var msg_result = parseRpcMessage(alloc, message_json);
        defer msg_result.deinit();

        switch (msg_result) {
            .request_result  => |request_result| {
                const writer = req_response_buf.writer(alloc);
                const response_written = switch (request_result.request_msg) {
                    .batch   => |reqs| try processRpcBatch(alloc,  reqs, self.req_dispatcher, writer),
                    .request => |req|  try processRpcRequest(alloc, req, self.req_dispatcher, "", writer),
                };
                self.logger.log("runMessage", "req_response_json", req_response_buf.items);
                return if (response_written) .request_has_response else .request_no_response;
            },
            .response_result => |response_result| {
                try processResponseResult(alloc, response_result, self.res_dispatcher);
                return .response_processed;
            },
        }
    }
};

pub const MessageRunResult = enum {
    request_has_response,
    request_no_response,
    response_processed,
};


