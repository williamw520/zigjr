// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const request = @import("jsonrpc/request.zig");
const response = @import("jsonrpc/response.zig");
const msg_handler = @import("jsonrpc/msg_handler.zig");
const rpc_registry = @import("jsonrpc/rpc_registry.zig");
const errors = @import("jsonrpc/errors.zig");
pub const messages = @import("jsonrpc/messages.zig");

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

pub const handleJsonRequest = msg_handler.handleJsonRequest;
pub const handleRequestToJson = msg_handler.handleRequestToJson;
pub const handleRequestToResponse = msg_handler.handleRequestToResponse;
pub const handleJsonResponse = msg_handler.handleJsonResponse;
pub const handleRpcRequest = msg_handler.handleRpcRequest;
pub const handleRpcRequests = msg_handler.handleRpcRequests;
pub const DispatchResult = msg_handler.DispatchResult;
pub const DispatchErrors = msg_handler.DispatchErrors;

pub const RpcRegistry = rpc_registry.RpcRegistry;
pub const RegistrationErrors = rpc_registry.RegistrationErrors;

pub const ErrorCode = errors.ErrorCode;
pub const JrErrors = errors.JrErrors;


test {
    _ = @import("tests/request_tests.zig");
    _ = @import("tests/response_tests.zig");
    _ = @import("tests/stream_tests.zig");
    _ = @import("tests/rpc_registry_tests.zig");
    _ = @import("tests/json_tests.zig");
    _ = @import("tests/tests.zig");
}


