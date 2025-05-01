// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const req_parser = @import("jsonrpc/req_parser.zig");
const res_parser = @import("jsonrpc/res_parser.zig");
const messages = @import("jsonrpc/messages.zig");
const responder = @import("jsonrpc/responder.zig");
const dispatcher = @import("dispatch/dispatcher.zig");
const jsonrpc_errors = @import("jsonrpc/jsonrpc_errors.zig");
const dispatcher_errors = @import("dispatch/dispatch_erros.zig");

pub const parseRequest = req_parser.parseRequest;
pub const parseRequestReader = req_parser.parseRequestReader;
pub const parseResponse = res_parser.parseResponse;
pub const RpcMessage = req_parser.RpcMessage;
pub const RpcRequest = req_parser.RpcRequest;
pub const RpcId = req_parser.RpcId;

pub const respond = responder.respond;
pub const DispatchResult = responder.DispatchResult;

pub const requestJson = messages.requestJson;
pub const batchJson = messages.batchJson;
pub const responseJson = messages.responseJson;
pub const responseErrorJson = messages.responseErrorJson;
pub const responseErrorDataJson = messages.responseErrorDataJson;

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
}


