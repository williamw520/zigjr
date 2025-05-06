// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const req_parser = @import("jsonrpc/request_parser.zig");
const res_parser = @import("jsonrpc/response_parser.zig");
const runner = @import("jsonrpc/runner.zig");
const dispatcher = @import("dispatch/dispatcher.zig");
const jsonrpc_errors = @import("jsonrpc/jsonrpc_errors.zig");
const dispatcher_errors = @import("dispatch/dispatch_erros.zig");
pub const messages = @import("jsonrpc/messages.zig");

pub const parseRequest = req_parser.parseRequest;
pub const parseRequestReader = req_parser.parseRequestReader;
pub const RequestResult = res_parser.RequestResult;
pub const RpcRequestMessage = req_parser.RpcRequestMessage;
pub const RpcRequest = req_parser.RpcRequest;
pub const RpcId = req_parser.RpcId;
pub const ReqError = req_parser.ReqError;

pub const parseResponse = res_parser.parseResponse;
pub const ResponseResult = res_parser.ResponseResult;
pub const RpcResponseMessage = res_parser.RpcResponseMessage;
pub const RpcResponse = res_parser.RpcResponse;
pub const RpcResponseErr = res_parser.RpcResponseErr;

pub const runRequest = runner.runRequest;
pub const runRequestBatch = runner.runRequestBatch;
pub const runRequestJson = runner.runRequestJson;
pub const runResponseJson = runner.runResponseJson;
pub const DispatchResult = runner.DispatchResult;

pub const Registry = dispatcher.Registry;

pub const ErrorCode = jsonrpc_errors.ErrorCode;
pub const JrErrors = jsonrpc_errors.JrErrors;
pub const RegistrationErrors = dispatcher_errors.RegistrationErrors;
pub const DispatchErrors = dispatcher_errors.DispatchErrors;


test {
    _ = @import("tests/request_tests.zig");
    _ = @import("tests/response_tests.zig");
    _ = @import("tests/dispatcher_tests.zig");
    _ = @import("tests/tests.zig");
    _ = @import("tests/stream_tests.zig");
}


