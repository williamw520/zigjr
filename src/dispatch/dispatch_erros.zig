// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

// Handler registration errors or dispatching errors.
pub const RegistrationErrors = error {
    InvalidMethodName,
    HandlerNotFunction,
    MissingAllocator,
    HandlerInvalidParameter,
    HandlerInvalidParameterType,
    HandlerTooManyParams,
    MismatchedParameterCountsForRawParams,
    InvalidParamTypeForRawParams,
};

pub const DispatchErrors = error {
    NoHandlerForArrayParam,
    NoHandlerForObjectParam,
    MismatchedParameterCounts,
    MethodNotFound,
    InvalidParams,
    WrongRequestParamTypeForRawParams,
};

