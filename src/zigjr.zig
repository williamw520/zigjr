// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const parser = @import("jsonrpc/parser.zig");
const responder = @import("jsonrpc/responder.zig");
const dispatcher = @import("dispatch/dispatcher.zig");
const jsonrpc_errors = @import("jsonrpc/jsonrpc_errors.zig");
const dispatcher_errors = @import("dispatch/dispatch_erros.zig");

pub const parseJson = parser.parseJson;
pub const parseReader = parser.parseReader;
pub const response = responder.response;
pub const parseResponse = responder.parseResponse;

pub const RpcMessage = parser.RpcMessage;
pub const RpcRequest = parser.RpcRequest;
pub const RpcId = parser.RpcId;

pub const Registry = dispatcher.Registry;

pub const ErrorCode = jsonrpc_errors.ErrorCode;
pub const JrErrors = jsonrpc_errors.JrErrors;
pub const RegistrationErrors = dispatcher_errors.RegistrationErrors;
pub const DispatchErrors = dispatcher_errors.DispatchErrors;


test {
    _ = @import("tests/parser_tests.zig");
    _ = @import("tests/responder_tests.zig");
    _ = @import("tests/dispatcher_tests.zig");
    _ = @import("tests/tests.zig");
}

