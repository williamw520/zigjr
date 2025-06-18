// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const request = @import("jsonrpc/request.zig");
const response = @import("jsonrpc/response.zig");
pub const errors = @import("jsonrpc/errors.zig");
pub const messages = @import("jsonrpc/messages.zig");
const msg_handler = @import("rpc/msg_handler.zig");
pub const pipeline = @import("rpc/pipeline.zig");
const dispatcher = @import("rpc/dispatcher.zig");
const rpc_registry = @import("rpc/rpc_registry.zig");
const json_call = @import("rpc/json_call.zig");
const stream = @import("streaming/stream.zig");

pub const parseRpcRequest = request.parseRpcRequest;
pub const RpcRequestResult = request.RpcRequestResult;
pub const RpcRequestMessage = request.RpcRequestMessage;
pub const RpcRequest = request.RpcRequest;
pub const RpcId = request.RpcId;
pub const RpcRequestError = request.RpcRequestError;

pub const parseRpcResponse = response.parseRpcResponse;
pub const RpcResponseResult = response.RpcResponseResult;
pub const RpcResponseMessage = response.RpcResponseMessage;
pub const RpcResponse = response.RpcResponse;
pub const RpcResponseError = response.RpcResponseError;

pub const RequestDispatcher = dispatcher.RequestDispatcher;
pub const ResponseDispatcher = dispatcher.ResponseDispatcher;
pub const DispatchResult = dispatcher.DispatchResult;
pub const DispatchErrors = dispatcher.DispatchErrors;

pub const handleJsonRequest = msg_handler.handleJsonRequest;
pub const handleRequestToJson = msg_handler.handleRequestToJson;
pub const handleRequestToResponse = msg_handler.handleRequestToResponse;
pub const handleJsonResponse = msg_handler.handleJsonResponse;

pub const DelimiterStream = stream.DelimiterStream;
pub const DelimiterStreamOptions = stream.DelimiterStreamOptions;
pub const ContentLengthStream = stream.ContentLengthStream;
pub const ContentLengthStreamOptions = stream.ContentLengthStreamOptions;
pub const Logger = stream.Logger;
pub const NopLogger = stream.NopLogger;
pub const DbgLogger = stream.DbgLogger;
pub const FileLogger = stream.FileLogger;

pub const JsonStr = json_call.JsonStr;

pub const RpcRegistry = rpc_registry.RpcRegistry;
pub const RegistrationErrors = rpc_registry.RegistrationErrors;

pub const ErrorCode = errors.ErrorCode;
pub const JrErrors = errors.JrErrors;


test {
    // _ = @import("tests/request_tests.zig");
    _ = @import("tests/response_tests.zig");
    // _ = @import("tests/stream_tests.zig");
    // _ = @import("tests/rpc_registry_tests.zig");
    // _ = @import("tests/json_call_tests.zig");
    // _ = @import("tests/tests.zig");
}


