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
pub const composer = @import("jsonrpc/composer.zig");
pub const pipeline = @import("rpc/rpc_pipeline.zig");
const dispatcher = @import("rpc/dispatcher.zig");
const rpc_registry = @import("rpc/rpc_registry.zig");
pub const stream = @import("streaming/stream.zig");
pub const frame = @import("streaming/frame.zig");
const logger = @import("rpc/logger.zig");

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

pub const RequestPipeline = pipeline.RequestPipeline;
pub const ResponsePipeline = pipeline.ResponsePipeline;

pub const Logger = logger.Logger;
pub const NopLogger = logger.NopLogger;
pub const DbgLogger = logger.DbgLogger;
pub const FileLogger = logger.FileLogger;

pub const RpcRegistry = rpc_registry.RpcRegistry;
pub const RegistrationErrors = rpc_registry.RegistrationErrors;
pub const JsonStr = @import("rpc/json_call.zig").JsonStr;

pub const ErrorCode = errors.ErrorCode;
pub const JrErrors = errors.JrErrors;

