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
const registry = @import("jsonrpc/registry.zig");
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

pub const handleRequest = runner.handleRequest;
pub const handleRequestBatch = runner.handleRequestBatch;
pub const handleRequestJson = runner.handleRequestJson;
pub const handleResponseJson = runner.handleResponseJson;
pub const RunResult = runner.RunResult;
pub const RunErrors = runner.RunErrors;

pub const Registry = registry.Registry;
pub const RegistrationErrors = registry.RegistrationErrors;

pub const ErrorCode = errors.ErrorCode;
pub const JrErrors = errors.JrErrors;


test {
    _ = @import("tests/request_tests.zig");
    _ = @import("tests/response_tests.zig");
    _ = @import("tests/stream_tests.zig");
    _ = @import("tests/dispatcher_tests.zig");
}


