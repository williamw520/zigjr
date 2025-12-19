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
const ArenaAllocator = std.heap.ArenaAllocator;

const zigjr = @import("../zigjr.zig");

const parseRpcRequest = zigjr.parseRpcRequest;
const RpcRequest = zigjr.RpcRequest;
const RpcId = zigjr.RpcId;
const RpcRequestResult = zigjr.RpcRequestResult;

const FrameData = zigjr.frame.FrameData;

const parseRpcResponse = zigjr.parseRpcResponse;
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

const dispatcher_z = @import("../rpc/dispatcher.zig");
const RequestDispatcher = dispatcher_z.RequestDispatcher;
const DispatchResult = dispatcher_z.DispatchResult;
const DispatchErrors = dispatcher_z.DispatchErrors;
const DispatchCtxImpl = dispatcher_z.DispatchCtxImpl;
const ResponseDispatcher = dispatcher_z.ResponseDispatcher;

var nopLogger = zigjr.NopLogger{};


/// Pipeline to process request.
/// Not thread safe.  Each worker thread should have a separate pipeline instance.
pub const RequestPipeline = struct {
    alloc:          Allocator,
    arena_ptr:      *ArenaAllocator, // arena needs to be a ptr to the struct to survive copying.
    arena_alloc:    Allocator,
    req_dispatcher: RequestDispatcher,
    logger:         zigjr.Logger,   // TODO: remove, use the logger in dc.
    response_buf:   std.Io.Writer.Allocating,
    dc:             DispatchCtxImpl,

    pub fn init(alloc: Allocator, req_dispatcher: RequestDispatcher, logger: ?zigjr.Logger) error{OutOfMemory}!RequestPipeline {
        const l = logger orelse zigjr.Logger.implBy(&nopLogger);
        l.start("[RequestPipeline.init] Logging starts");

        const arena_ptr = try alloc.create(ArenaAllocator);
        arena_ptr.* = ArenaAllocator.init(alloc);
        const arena_alloc = arena_ptr.allocator();
        return .{
            .alloc = alloc,
            .arena_ptr = arena_ptr,
            .arena_alloc = arena_alloc,
            .req_dispatcher = req_dispatcher,
            .logger = l,
            .response_buf = std.Io.Writer.Allocating.init(alloc),
            .dc = .{
                .arena = arena_alloc,
                .logger = l,
            },
        };
    }

    pub fn deinit(self: *RequestPipeline) void {
        self.logger.stop("[RequestPipeline.deinit] Logging stops");
        self.response_buf.deinit();
        self.arena_ptr.deinit();
        const backing_alloc = self.arena_ptr.child_allocator;
        backing_alloc.destroy(self.arena_ptr);
    }

    /// Parse the JSON-RPC request message, run the dispatcher on request(s), 
    /// and buffer up the JSON-RPC response(s) in an internal buffer.
    /// Call responseJson() to retrieve the buffered response(s).
    /// The JSON request message can contain a single request or a batch of requests.
    /// Error is turned into a JSON-RPC error response message.
    /// The function returns a RunStatus indicating whether any response has been written,
    /// as notification requests have no response.
    pub fn runRequest(self: *RequestPipeline, request_json: []const u8) std.Io.Writer.Error!RunStatus {
        self.logger.log("RequestPipeline.runRequest", "request ", request_json);
        self.resetResponseBuffer();

        var parsed_request = parseRpcRequest(self.alloc, request_json);
        defer parsed_request.deinit();
        const run_status = switch (parsed_request.request_msg) {
            .batch   => |reqs| try self.processRpcBatch(reqs),
            .request => |*req| try self.processRpcRequest(req, "", true),
        };
        if (run_status.hasReply()) {
            self.logger.log("RequestPipeline.runRequest", "response", self.responseJson());
        }
        return run_status;
    }

    /// Return the current buffered up response JSON; it will be overwritten on the next runRequest() call.
    pub fn responseJson(self: *RequestPipeline) []const u8 {
        return self.response_buf.written();
    }

    fn resetResponseBuffer(self: *RequestPipeline) void {
        self.response_buf.clearRetainingCapacity();
    }

    /// Run the request and return the response(s) in a RpcResponseResult. Same as runRequest().
    /// The returned RpcResponseResult should be freed with the passed in allocator.
    /// This is mainly for testing.
    pub fn runRequestToResponse(self: *RequestPipeline, alloc: Allocator,
                                request_json: []const u8) !RpcResponseResult {
        if ((try self.runRequest(request_json)).hasReply()) {
            return zigjr.parseRpcResponseOwned(alloc, self.responseJson(), .{});
        } else {
            return .{};
        }
    }

    /// Run the request and parse the result JSON to type T.
    /// The returned Parsed(T) should be freed with its .deinit().
    /// Same behaviour as runRequest(). Mainly for testing.
    /// This skips the steps decoding the response/result, and goes directly to the result object.
    pub fn runRequestToResult(self: *RequestPipeline, alloc: Allocator,
                              request_json: []const u8, comptime T: type) !?std.json.Parsed(T) {
        var rpc_response_result = try self.runRequestToResponse(alloc, request_json);
        defer rpc_response_result.deinit();
        const rpc_response = try rpc_response_result.response();
        if (rpc_response.hasErr()) return JrErrors.ResponseHasError;
        if (!rpc_response.hasResult()) return null;
        return try std.json.parseFromValue(T, alloc, rpc_response.result, .{});
    }

    fn processRpcBatch(self: *RequestPipeline, reqs: []RpcRequest) std.Io.Writer.Error!RunStatus {
        defer {
            _ = self.arena_ptr.reset(.{ .retain_with_limit = 4096 });   // TODO: configurable limit
        }
        var has_replied: bool = false;
        var end_stream: bool = false;
        try self.responseWriter().writeAll("[");
        for (reqs) |*req| {
            const delimiter = if (has_replied) ", " else "";
            const r_status  = try self.processRpcRequest(req, delimiter, false);
            has_replied     = has_replied or r_status.hasReply();
            end_stream      = end_stream  or r_status.end_stream;
        }
        try self.responseWriter().writeAll("]");
        return RunStatus.asRequest(true, end_stream);   // batch always has some output like "[]"
    }

    /// Handle request's error, dispatch the request, and write the response.
    /// Returns true if a response message is written, false for not as notification has no response.
    fn processRpcRequest(self: *RequestPipeline, req: *const RpcRequest, delimiter: []const u8,
                         resetArena: bool) std.Io.Writer.Error!RunStatus {
        defer {
            if (resetArena)
                _ = self.arena_ptr.reset(.{ .retain_with_limit = 4096 });   // TODO: configurable limit
        }
        if (try self.fmtRequestError(req)) return RunStatus.asRequestReplied();

        self.dc.request = req;
        errdefer {
            // In case of std.Io.Writer.Error.
            self.dc.result = DispatchResult.asNone();
            self.req_dispatcher.dispatchEnd(&self.dc);
            self.dc.reset();
        }
        const d_result = self.req_dispatcher.dispatch(&self.dc) catch |err| blk: {
            break :blk DispatchResult.withAnyErr(err);  // Turn dispatch error into DispatchResult.err.
        };
        const r_status = try self.fmtResponse(&d_result, req, delimiter);
        self.dc.result = d_result;
        self.req_dispatcher.dispatchEnd(&self.dc);
        self.dc.reset();
        return r_status;
    }

    fn responseWriter(self: *RequestPipeline) *std.Io.Writer {
        return &self.response_buf.writer;
    }

    fn fmtRequestError(self: *RequestPipeline, req: *const RpcRequest) std.Io.Writer.Error!bool {
        if (req.hasError()) {   // request has parsing or validation error.
            try composer.writeErrorResponseJson(req.id, req.err().code, req.err().err_msg, self.responseWriter());
            return true;
        }
        return false;
    }

    fn fmtResponse(self: *RequestPipeline, dresult: *const DispatchResult, req: *const RpcRequest,
                      delimiter: []const u8) std.Io.Writer.Error!RunStatus {
        switch (dresult.*) {
            .none => {
                return RunStatus.asRequestNone();       // notification request has no response written.
            },
            .result => |json| {
                if (req.id.isNotification()) {
                    return RunStatus.asRequestNone();   // notification request has no response written.
                }
                try self.responseWriter().writeAll(delimiter);
                try composer.writeResponseJson(req.id, json, self.responseWriter());
                return RunStatus.asRequestReplied();    // has response data written
            },
            .err => |err| {
                try self.responseWriter().writeAll(delimiter);
                if (err.data)|data_json| {
                    try composer.writeErrorDataResponseJson(req.id, err.code, err.msg, data_json, self.responseWriter());
                } else {
                    try composer.writeErrorResponseJson(req.id, err.code, err.msg, self.responseWriter());
                }
                return RunStatus.asRequestReplied();    // has response data written
            },
            .end_stream =>
                return RunStatus.asRequestEndStream(),
        }
    }
    
};

pub const RunStatus = struct {
    kind: union(enum) {         // status for processing request or response.
        request: struct {
            replied: bool,      // request has response data written; notification has no reply.
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

    /// Request processing has replying responses.
    pub fn hasReply(self: RunStatus) bool {
        return if (self.kind == .request) self.kind.request.replied else false;
    }

};


pub const ResponsePipeline = struct {
    alloc:          Allocator,
    arena_ptr:      *ArenaAllocator, // arena needs to be a ptr to the struct to survive copying.
    arena_alloc:    Allocator,
    res_dispatcher: ResponseDispatcher,

    pub fn init(alloc: Allocator, res_dispatcher: ResponseDispatcher) error{OutOfMemory}!ResponsePipeline {
        const arena_ptr = alloc.create(ArenaAllocator) catch unreachable;
        arena_ptr.* = ArenaAllocator.init(alloc);
        const arena_alloc = arena_ptr.allocator();
        return .{
            .alloc = alloc,
            .arena_ptr = arena_ptr,
            .arena_alloc = arena_alloc,
            .res_dispatcher = res_dispatcher,
        };
    }

    pub fn deinit(self: *ResponsePipeline) void {
        self.arena_ptr.deinit();
        const backing_alloc = self.arena_ptr.child_allocator;
        backing_alloc.destroy(self.arena_ptr);
    }
    
    /// Parse the JSON response message and run the dispatcher on RpcResponse(s).
    /// The JSON response message can contain a single response or a batch of responses.
    /// The 'anytype' dispatcher needs to have a dispatch() method with !void return type.
    /// Any parse error is returned to the caller and the dispatcher is not called.
    /// Any error coming from the dispatcher is passed back to caller.
    /// For batch responses, the first error from the dispatcher stops the processing.
    pub fn runResponse(self: *const ResponsePipeline, response_json: []const u8,
                       headers: ?std.StringHashMap([]const u8)) !RunStatus {
        _=headers;  // frame-level headers. May have character encoding. See FrameData.headers in frame.zig.

        var response_result: RpcResponseResult = parseRpcResponse(self.alloc, response_json);
        defer response_result.deinit();
        return try self.processResponseResult(response_result);
    }

    fn processResponseResult(self: *const ResponsePipeline, response_result: RpcResponseResult) anyerror!RunStatus {
        defer {
            _ = self.arena_ptr.reset(.{ .retain_with_limit = 4096 });   // TODO: configurable limit
        }

        // Any errors (parsing or others) are forwarded to the handlers via the dispatcher.
        const run_status = switch (response_result.response_msg) {
            .response   => |rpc_response| {
                return if (try self.res_dispatcher.dispatch(self.arena_alloc, rpc_response))
                    RunStatus.asResponse()
                else
                    RunStatus.asResponseEndStream();
            },
            .batch      => |rpc_responses| {
                var continuing = true;
                for (rpc_responses) |rpc_response| {
                    const to_continue = try self.res_dispatcher.dispatch(self.arena_alloc, rpc_response);
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
        return run_status;
    }
};


pub const MessagePipeline = struct {
    alloc:          Allocator,
    req_pipeline:   RequestPipeline,
    res_pipeline:   ResponsePipeline,
    logger:         zigjr.Logger,

    pub fn init(alloc: Allocator, req_dispatcher: RequestDispatcher, res_dispatcher: ResponseDispatcher,
                logger: ?zigjr.Logger) error{OutOfMemory}!MessagePipeline {
        const l = logger orelse zigjr.Logger.implBy(&nopLogger);
        l.start("[MessagePipeline] Logging starts");
        
        return .{
            .alloc = alloc,
            .logger = l,
            .req_pipeline = try RequestPipeline.init(alloc, req_dispatcher, logger),
            .res_pipeline = try ResponsePipeline.init(alloc, res_dispatcher),
        };
    }

    pub fn deinit(self: *MessagePipeline) void {
        self.logger.stop("[MessagePipeline] Logging stops");
        self.req_pipeline.deinit();
        self.res_pipeline.deinit();
    }

    pub fn runMessage(self: *MessagePipeline, message_json: []const u8) anyerror!RunStatus {
        self.logger.log("runMessage", "message_json ", message_json);

        var msg_result = parseRpcMessage(self.alloc, message_json);
        defer msg_result.deinit();

        switch (msg_result) {
            .request_result  => |request_result| {
                const run_status = switch (request_result.request_msg) {
                    .batch   => |reqs| try self.req_pipeline.processRpcBatch(reqs),
                    .request => |req|  try self.req_pipeline.processRpcRequest(&req, "", true),
                };
                if (run_status.hasReply()) {
                    self.logger.log("runMessage", "request message processed; response_json", self.req_pipeline.responseJson());
                }
                return run_status;
            },
            .response_result => |response_result| {
                const run_status = try self.res_pipeline.processResponseResult(response_result);
                self.logger.log("runMessage", "response message processed", "");
                return run_status;
            },
        }
    }

    /// Return the current buffered up response JSON for a request message.
    /// It will be overwritten on the next runMessage() call with a request message.
    /// It's not applied to a response message. Check the RunStatus of runMessage().
    pub fn reqResponseJson(self: *MessagePipeline) []const u8 {
        return self.req_pipeline.responseJson();
    }

};


