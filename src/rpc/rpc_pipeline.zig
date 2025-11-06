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

const FrameData = zigjr.frame.FrameData;

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
const WriteAllocError = zigjr.errors.WriteAllocError;

const composer = zigjr.composer;

const RequestDispatcher = @import ("dispatcher.zig").RequestDispatcher;
const ResponseDispatcher = @import ("dispatcher.zig").ResponseDispatcher;
const DispatchResult = @import ("dispatcher.zig").DispatchResult;
var nopLogger = zigjr.NopLogger{};

const DupWriter = @import("../streaming/DupWriter.zig");


pub const RequestOpts = struct {
};

pub const RequestPipeline = struct {
    alloc:          Allocator,
    req_dispatcher: RequestDispatcher,
    logger:         zigjr.Logger,
    buf_writer:     std.Io.Writer.Allocating,

    pub fn init(alloc: Allocator, req_dispatcher: RequestDispatcher, logger: ?zigjr.Logger) @This() {
        const l = logger orelse zigjr.Logger.implBy(&nopLogger);
        l.start("[RequestPipeline.init] Logging starts");
        return .{
            .alloc = alloc,
            .req_dispatcher = req_dispatcher,
            .logger = l,
            .buf_writer = std.Io.Writer.Allocating.init(alloc),
        };
    }

    pub fn deinit(self: *RequestPipeline) void {
        self.logger.stop("[RequestPipeline.deinit] Logging stops");
        self.buf_writer.deinit();
    }

    /// Parse the JSON-RPC request message, run the dispatcher on request(s), 
    /// and write the JSON-RPC response(s) to the response_buf.
    /// The JSON request message can contain a single request or a batch of requests.
    /// Error is turned into a JSON-RPC error response message.
    /// The function returns a boolean flag indicating whether any response has been written,
    /// as notification requests have no response.
    pub fn runRequest(self: *RequestPipeline, request_json: []const u8, writer: *std.Io.Writer,
                      req_opts: RequestOpts) std.Io.Writer.Error!RunStatus {
        _=req_opts;

        self.logger.log("RequestPipeline.runRequest", "request ", request_json);
        var parsed_request = parseRpcRequest(self.alloc, request_json);
        defer parsed_request.deinit();
        self.buf_writer.clearRetainingCapacity();
        const run_status = switch (parsed_request.request_msg) {
            .batch   => |reqs| try processRpcBatch(reqs, self.req_dispatcher, &self.buf_writer.writer),
            .request => |req|  try processRpcRequest(req, self.req_dispatcher, "", &self.buf_writer.writer),
        };
        if (run_status.isReplied()) {
            try writer.writeAll(self.buf_writer.written());
            self.logger.log("RequestPipeline.runRequest", "response", self.buf_writer.written());
        }
        return run_status;
    }

    /// Run the request and return the response(s) as a JSON string. Same as runRequest().
    /// The returned response JSON should be freed with the passed in allocator.
    pub fn runRequestToJson(self: *RequestPipeline, alloc: Allocator,
                            request_json: []const u8) WriteAllocError!?[]const u8 {
        var response_buf = std.Io.Writer.Allocating.init(alloc);
        defer response_buf.deinit();
        const run_status = try self.runRequest(request_json, &response_buf.writer, .{});
        if (run_status.isReplied()) {
            return try response_buf.toOwnedSlice();
        } else {
            return null;
        }
    }

    /// Run the request and return the response(s) in a RpcResponseResult. Same as runRequest().
    /// The returned RpcResponseResult should be freed with the passed in allocator.
    /// This is mainly for testing.
    pub fn runRequestToResponse(self: *RequestPipeline, alloc: Allocator,
                                request_json: []const u8) !RpcResponseResult {
        const response_json = try self.runRequestToJson(alloc, request_json);
        if (response_json) |json| {
            return parseRpcResponseOwned(alloc, json, .{});
        } else {
            return .{};
        }        
    }
};

fn processRpcBatch(reqs: []RpcRequest, dispatcher: RequestDispatcher,
                   writer: *std.Io.Writer) std.Io.Writer.Error!RunStatus {
    var has_replied: bool = false;
    var end_stream: bool = false;
    try writer.writeAll("[");
    for (reqs) |req| {
        const delimiter = if (has_replied) ", " else "";
        const r_status  = try processRpcRequest(req, dispatcher, delimiter, writer);
        has_replied     = has_replied or r_status.isReplied();
        end_stream      = end_stream  or r_status.end_stream;
    }
    try writer.writeAll("]");
    return RunStatus.asRequest(true, end_stream);   // batch always has some output like "[]"
}

/// Handle request's error, dispatch the request, and write the response.
/// Returns true if a response message is written, false for not as notification has no response.
fn processRpcRequest(req: RpcRequest, req_dispatcher: RequestDispatcher,
                     delimiter: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!RunStatus {
    if (try handleRequestError(req, writer)) return RunStatus.asRequestReplied();
    errdefer req_dispatcher.dispatchEnd(req, DispatchResult.asNone());   // for std.Io.Writer.Error
    const d_result = try dispatchRequest(req, req_dispatcher);
    const r_status = try writeResponse(d_result, req, delimiter, writer);
    req_dispatcher.dispatchEnd(req, d_result);
    return r_status;
}

fn handleRequestError(req: RpcRequest, writer: *std.Io.Writer) std.Io.Writer.Error!bool {
    if (req.hasError()) {   // request has parsing or validation error.
        try composer.writeErrorResponseJson(req.id, req.err().code, req.err().err_msg, writer);
        return true;
    }
    return false;
}

fn dispatchRequest(req: RpcRequest, req_dispatcher: RequestDispatcher) std.Io.Writer.Error!DispatchResult {
    return req_dispatcher.dispatch(req) catch |err| {
        // Turn dispatching error into DispatchResult.err.
        // Handle errors here so dispatchers don't have to worry about error handling.
        return DispatchResult.withAnyErr(err);
    };
}

fn writeResponse(dresult: DispatchResult, req: RpcRequest, delimiter: []const u8,
                 writer: *std.Io.Writer) std.Io.Writer.Error!RunStatus {
    switch (dresult) {
        .none => {
            return RunStatus.asRequestNone();       // notification request has no response written.
        },
        .result => |json| {
            if (req.id.isNotification()) {
                return RunStatus.asRequestNone();   // notification request has no response written.
            }
            try writer.writeAll(delimiter);
            try composer.writeResponseJson(req.id, json, writer);
            return RunStatus.asRequestReplied();    // has response data written
        },
        .err => |err| {
            try writer.writeAll(delimiter);
            if (err.data)|data_json| {
                try composer.writeErrorDataResponseJson(req.id, err.code, err.msg, data_json, writer);
            } else {
                try composer.writeErrorResponseJson(req.id, err.code, err.msg, writer);
            }
            return RunStatus.asRequestReplied();    // has response data written
        },
        .end_stream =>
            return RunStatus.asRequestEndStream(),
    }
}

pub const RunStatus = struct {
    kind: union(enum) {         // status for processing request or response.
        request: struct {
            replied: bool,      // request has response data written
        },
        response: void,
    },   
    end_stream: bool = false,   // request/response handler wants to end the streaming session.

    pub fn asRequest(has_reply: bool, end_stream: bool) RunStatus {
        return .{
            .kind = .{
                .request = .{ .replied = has_reply }
            },
            .end_stream = end_stream,
        };
    }

    pub fn asRequestNone() RunStatus {
        return asRequest(false, false);
    }

    pub fn asRequestReplied() RunStatus {
        return asRequest(true, false);
    }

    pub fn asRequestEndStream() RunStatus {
        return asRequest(false, true);
    }

    pub fn asResponse() RunStatus {
        return .{
            .kind = .{
                .response = {}
            },
            .end_stream = false,
        };
    }

    pub fn asResponseEndStream() RunStatus {
        return .{
            .kind = .{
                .response = {}
            },
            .end_stream = true,
        };
    }

    pub fn isReplied(self: RunStatus) bool {
        return if (self.kind == .request) self.kind.request.replied else false;
    }

};


pub const ResponsePipeline = struct {
    alloc:          Allocator,
    res_dispatcher: ResponseDispatcher,

    pub fn init(alloc: Allocator, res_dispatcher: ResponseDispatcher) ResponsePipeline {
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
    pub fn runResponse(self: ResponsePipeline, response_json: []const u8,
                       headers: ?std.StringHashMap([]const u8)) !RunStatus {
        _=headers;  // frame-level headers. May have character encoding. See FrameData.headers in frame.zig.

        var response_result: RpcResponseResult = parseRpcResponse(self.alloc, response_json);
        defer response_result.deinit();
        return try processResponseResult(self.alloc, response_result, self.res_dispatcher);
    }

};

fn processResponseResult(alloc: Allocator, response_result: RpcResponseResult,
                         dispatcher: ResponseDispatcher) anyerror!RunStatus {
    // Any errors (parsing or others) are forwarded to the handlers via the dispatcher.
    return switch (response_result.response_msg) {
        .response   => |rpc_response| {
            return if (try dispatcher.dispatch(alloc, rpc_response))
                RunStatus.asResponse()
            else
                RunStatus.asResponseEndStream();
        },
        .batch      => |rpc_responses| {
            var continuing = true;
            for (rpc_responses) |rpc_response| {
                const to_continue = try dispatcher.dispatch(alloc, rpc_response);
                continuing = continuing and to_continue;
            }
            return if (continuing)
                RunStatus.asResponse()
            else
                RunStatus.asResponseEndStream();
        },
        .none       =>
            return RunStatus.asResponse(),
    };
}


pub const MessagePipeline = struct {
    req_dispatcher: RequestDispatcher,
    res_dispatcher: ResponseDispatcher,
    logger:         zigjr.Logger,
    buf_writer:     std.Io.Writer.Allocating,

    pub fn init(alloc: Allocator, req_dispatcher: RequestDispatcher, res_dispatcher: ResponseDispatcher,
                logger: ?zigjr.Logger) MessagePipeline {
        const l = logger orelse zigjr.Logger.implBy(&nopLogger);
        l.start("[MessagePipeline] Logging starts");
        return .{
            .logger = l,
            .req_dispatcher = req_dispatcher,
            .res_dispatcher = res_dispatcher,
            .buf_writer = std.Io.Writer.Allocating.init(alloc),
        };
    }

    pub fn deinit(self: *MessagePipeline) void {
        self.logger.stop("[MessagePipeline] Logging stops");
        self.buf_writer.deinit();
    }

    pub fn runMessage(self: *MessagePipeline, alloc: Allocator,
                      message_json: []const u8, writer: *std.Io.Writer,
                      req_opts: RequestOpts) anyerror!RunStatus {
        _=req_opts;

        self.logger.log("runMessage", "message_json ", message_json);
        var msg_result = parseRpcMessage(alloc, message_json);
        defer msg_result.deinit();
        self.buf_writer.clearRetainingCapacity();

        switch (msg_result) {
            .request_result  => |request_result| {
                const run_status = switch (request_result.request_msg) {
                    .batch   => |reqs| try processRpcBatch(reqs, self.req_dispatcher, &self.buf_writer.writer),
                    .request => |req|  try processRpcRequest(req, self.req_dispatcher, "", &self.buf_writer.writer),
                };
                if (run_status.isReplied()) {
                    self.logger.log("runMessage", "req_response_json", self.buf_writer.written());
                    try writer.writeAll(self.buf_writer.written());
                }
                return run_status;
            },
            .response_result => |response_result| {
                return try processResponseResult(alloc, response_result, self.res_dispatcher);
            },
        }
    }
};


