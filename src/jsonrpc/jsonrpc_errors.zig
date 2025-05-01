// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

// JSON-RPC 2.0 error codes.
pub const ErrorCode = enum(i32) {
    None = 0,
    ParseError = -32700,        // Invalid JSON was received by the server.
    InvalidRequest = -32600,    // The JSON sent is not a valid Request object.
    MethodNotFound = -32601,    // The method does not exist / is not available.
    InvalidParams = -32602,     // Invalid method parameter(s).
    InternalError = -32603,     // Internal JSON-RPC error.
    ServerError = -32000,       // -32000 to -32099 reserved for implementation defined errors.
};

pub const JrErrors = error {
    NotSingleRpcRequest,
    NotBatchRpcRequest,
    NotArray,
    NotObject,
    MissingIdForResponse,
    NotResultResponse,
    NotErrResponse,
    InvalidResponse,
    InvalidParamsType,
};


