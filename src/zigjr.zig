// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const request = @import("jsonrpc/request.zig");
const response = @import("jsonrpc/response.zig");
const runner = @import("jsonrpc/runner.zig");
const dispatcher = @import("jsonrpc/dispatcher.zig");
const errors = @import("jsonrpc/errors.zig");
pub const messages = @import("jsonrpc/messages.zig");

pub const parseRequest = request.parseRequest;
pub const parseRequestReader = request.parseRequestReader;
pub const RequestResult = response.RequestResult;
pub const RpcRequestMessage = request.RpcRequestMessage;
pub const RpcRequest = request.RpcRequest;
pub const RpcId = request.RpcId;
pub const ReqError = request.ReqError;

pub const parseResponse = response.parseResponse;
pub const ResponseResult = response.ResponseResult;
pub const RpcResponseMessage = response.RpcResponseMessage;
pub const RpcResponse = response.RpcResponse;
pub const RpcResponseErr = response.RpcResponseErr;

pub const runRequest = runner.runRequest;
pub const runRequestBatch = runner.runRequestBatch;
pub const runRequestJson = runner.runRequestJson;
pub const runResponseJson = runner.runResponseJson;
pub const DispatchResult = runner.DispatchResult;

pub const Registry = dispatcher.Registry;

pub const ErrorCode = errors.ErrorCode;
pub const JrErrors = errors.JrErrors;
pub const RegistrationErrors = dispatcher.RegistrationErrors;
pub const DispatchErrors = dispatcher.DispatchErrors;


test {
    _ = @import("tests/request_tests.zig");
    _ = @import("tests/response_tests.zig");
    _ = @import("tests/dispatcher_tests.zig");
    _ = @import("tests/stream_tests.zig");
}


