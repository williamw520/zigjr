// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const request = @import("jsonrpc/request.zig");
const response = @import("jsonrpc/response.zig");
const message = @import("jsonrpc/message.zig");
pub const errors = @import("jsonrpc/errors.zig");
pub const composer = @import("jsonrpc/composer.zig");
pub const pipeline = @import("rpc/rpc_pipeline.zig");
const dispatcher = @import("rpc/dispatcher.zig");
const rpc_dispatcher = @import("rpc/rpc_dispatcher.zig");
pub const stream = @import("streaming/stream.zig");
pub const frame = @import("streaming/frame.zig");
const logger = @import("rpc/logger.zig");
pub const json_call = @import("rpc/json_call.zig");

pub const parseRpcRequest = request.parseRpcRequest;
pub const parseRpcRequestOwned = request.parseRpcRequestOwned;
pub const RpcRequestResult = request.RpcRequestResult;
pub const RpcRequestMessage = request.RpcRequestMessage;
pub const RpcRequest = request.RpcRequest;
pub const RpcId = request.RpcId;
pub const RpcRequestError = request.RpcRequestError;

pub const parseRpcResponse = response.parseRpcResponse;
pub const parseRpcResponseOwned = response.parseRpcResponseOwned;
pub const RpcResponseResult = response.RpcResponseResult;
pub const RpcResponseMessage = response.RpcResponseMessage;
pub const RpcResponse = response.RpcResponse;
pub const RpcResponseError = response.RpcResponseError;

pub const parseRpcMessage = message.parseRpcMessage;

pub const RequestDispatcher = dispatcher.RequestDispatcher;
pub const ResponseDispatcher = dispatcher.ResponseDispatcher;
pub const DispatchResult = dispatcher.DispatchResult;
pub const DispatchErrors = dispatcher.DispatchErrors;
pub const DispatchCtx = json_call.DispatchCtx;

pub const RequestPipeline = pipeline.RequestPipeline;
pub const ResponsePipeline = pipeline.ResponsePipeline;
pub const MessagePipeline = pipeline.MessagePipeline;
pub const RunStatus = pipeline.RunStatus;

pub const Logger = logger.Logger;
pub const NopLogger = logger.NopLogger;
pub const DbgLogger = logger.DbgLogger;
pub const FileLogger = logger.FileLogger;

pub const RpcDispatcher = rpc_dispatcher.RpcDispatcher;
pub const RegistrationErrors = rpc_dispatcher.RegistrationErrors;
pub const JsonStr = @import("rpc/json_call.zig").JsonStr;

pub const ErrorCode = errors.ErrorCode;
pub const JrErrors = errors.JrErrors;


test {
    // _ = @import("tests/request_tests.zig");
    // _ = @import("tests/response_tests.zig");
    // _ = @import("tests/message_tests.zig");
    // _ = @import("tests/frame_tests.zig");
    // _ = @import("tests/stream_tests.zig");
    // _ = @import("tests/rpc_dispatcher_tests.zig");
    _ = @import("tests/json_call_tests.zig");
    // _ = @import("tests/misc_tests.zig");
    // _ = @import("streaming/BufReader.zig");
    // _ = @import("streaming/DupWriter.zig");
}


