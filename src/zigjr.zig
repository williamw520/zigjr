// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const parser = @import("parser.zig");
const dispatcher = @import("dispatcher.zig");
const errors = @import("errors.zig");

pub const parseJson = parser.parseJson;
pub const parseReader = parser.parseReader;
pub const RpcMessage = parser.RpcMessage;
pub const RpcRequest = parser.RpcRequest;
pub const RpcId = parser.RpcId;

pub const Registry = dispatcher.Registry;

pub const ErrorCode = errors.ErrorCode;
pub const JrErrors = errors.JrErrors;
pub const RegistrationErrors = errors.RegistrationErrors;
pub const DispatchErrors = errors.DispatchErrors;


test {
    _ = @import("tests/parser_tests.zig");
    _ = @import("tests/dispatcher_tests.zig");
    _ = @import("tests/tests.zig");
}

