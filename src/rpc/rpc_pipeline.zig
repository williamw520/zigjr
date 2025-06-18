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

const parseRpcResponse = zigjr.parseRpcResponse;
const RpcResponse = zigjr.RpcResponse;
const RpcResponseResult = zigjr.RpcResponseResult;
const RpcResponseMessage = zigjr.RpcResponseMessage;

const ErrorCode = zigjr.errors.ErrorCode;
const JrErrors = zigjr.errors.JrErrors;
const AllocError = zigjr.errors.AllocError;

const messages = zigjr.messages;

const dispatcher =  @import ("dispatcher.zig");
const RequestDispatcher = dispatcher.RequestDispatcher;
const ResponseDispatcher = dispatcher.ResponseDispatcher;
const DispatchResult = dispatcher.DispatchResult;


pub const RequestPipeline = struct {
    alloc:          Allocator,
    req_dispatcher: RequestDispatcher,

    pub fn init(alloc: Allocator, req_dispatcher: RequestDispatcher) @This() {
        return .{
            .alloc = alloc,
            .req_dispatcher = req_dispatcher,
        };
    }

    /// Parse the JSON-RPC request message, run the dispatcher on request(s), 
    /// and write the JSON-RPC response(s) to the writer.
    /// The JSON request message can contain a single request or a batch of requests.
    /// Error is turned into a JSON-RPC error response message.
    /// The function returns a boolean flag indicating whether any responses have been written,
    /// as notification requests have no response.
    ///
    /// The 'anytype' dispatcher needs to have a dispatch() method returning a DispatchResult.
    /// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
    pub fn runRequest(self: @This(), request_json: []const u8, writer: anytype) AllocError!bool {
        var parsed_result = parseRpcRequest(self.alloc, request_json);
        defer parsed_result.deinit();
        switch (parsed_result.request_msg) {
            .request    => |req| {
                return try self.runRpcRequest(req, writer, "");
            },
            .batch      => |reqs| {
                var count: usize = 0;
                try writer.writeAll("[");
                for (reqs) |req| {
                    const delimiter = if (count > 0) ", " else "";
                    if (try self.runRpcRequest(req, writer, delimiter)) {
                        count += 1;
                    }
                }
                try writer.writeAll("]");
                return true;
            },
        }
    }

    /// Parse the JSON-RPC request message, run the dispatcher on request(s), 
    /// and return the JSON-RPC response(s) as a JSON string.
    /// The JSON request message can contain a single request or a batch of requests.
    /// Error is turned into a JSON-RPC error response message.
    /// The function can return null, as notification requests have no response.
    ///
    /// The 'anytype' dispatcher needs to have a dispatch() method returning a DispatchResult.
    /// The 'anytype' dispatcher needs to have a free() method to free the DispatchResult.
    pub fn runRequestToJson(self: @This(), request_json: []const u8) AllocError!?[]const u8 {
        var response_buf = ArrayList(u8).init(self.alloc);
        if (try self.runRequest(request_json, response_buf.writer())) {
            return try response_buf.toOwnedSlice();
        } else {
            response_buf.deinit();
            return null;
        }
    }

    /// Parse the JSON-RPC request message, run the dispatcher on request(s), 
    /// parse the JSON-RPC response message, and return the RpcResponseResult.
    /// Usually after handling the request, the JSON-RPC response message is sent back to the client.
    /// The client then parses the JSON-RPC response message.  This skips all those and directly
    /// parses the JSON-RPC response message in one shot.  This is mainly for testing.
    pub fn runRequestToResponse(self: @This(), request_json: []const u8) !RpcResponseResult {
        const response_json = try self.runRequestToJson(request_json) orelse "";
        defer self.alloc.free(response_json);
        return try parseRpcResponse(self.alloc, response_json);
    }

    /// Run the dispatcher on the RpcRequest and write the response JSON to the writer.
    /// Returns true if a response message is written, false for not as notification has no response.
    /// Any error coming from the dispatcher is passed back to caller.
    ///
    /// The prefix is written to the writer before the response message.
    /// Prefix would not be written for a notification request.
    fn runRpcRequest(self: @This(), req: RpcRequest, writer: anytype, prefix: []const u8) AllocError!bool {
        if (req.hasError()) {
            // Return an error response for the parsing or validation error on the request.
            try messages.writeErrorResponseJson(req.id, req.err().code, req.err().err_msg, writer);
            return true;
        }

        // Call the request dispatcher to handle the request.
        const dresult: DispatchResult = call: {
            break :call self.req_dispatcher.dispatch(self.alloc, req) catch |err| {
                // Turn dispatching error into DispatchResult.err.
                // Handle errors here so dispatchers don't have to worry about error handling.
                break :call DispatchResult.withAnyErr(err);
            };
        };
        // Clean up the result at the end of dispatching.
        defer self.req_dispatcher.dispatchEnd(self.alloc, req, dresult);

        switch (dresult) {
            .none => {
                return false;   // notification request has no result.
            },
            .result => |json| {
                if (req.id.isNotification()) {
                    return false;
                }
                try writer.writeAll(prefix);
                try messages.writeResponseJson(req.id, json, writer);
                return true;
            },
            .err => |err| {
                try writer.writeAll(prefix);
                if (err.data)|data_json| {
                    try messages.writeErrorDataResponseJson(req.id, err.code, err.msg, data_json, writer);
                } else {
                    try messages.writeErrorResponseJson(req.id, err.code, err.msg, writer);
                }
                return true;
            },
        }
    }

};


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
    pub fn handleJsonResponse(self: @This(), response_json: ?[]const u8) !void {
        var parsed_result: RpcResponseResult = try parseRpcResponse(self.alloc, response_json);
        defer parsed_result.deinit();
        const response_msg: RpcResponseMessage = parsed_result.response_msg;
        return switch (response_msg) {
            .response   => |rpc_response|  try self.res_dispatcher.dispatch(self.alloc, rpc_response),
            .batch      => |rpc_responses| for (rpc_responses)|rpc_response| {
                try self.res_dispatcher.dispatch(self.alloc, rpc_response);
            },
            .none       => {},
        };
    }

};


