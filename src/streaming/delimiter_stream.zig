// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;
const ArrayList = std.ArrayList;
const bufferedWriter = std.io.bufferedWriter;

const req_parser = @import("../jsonrpc/request_parser.zig");
const RpcRequest = req_parser.RpcRequest;
const RpcId = req_parser.RpcId;

const jsonrpc_errors = @import("../jsonrpc/jsonrpc_errors.zig");
const ErrorCode = jsonrpc_errors.ErrorCode;
const JrErrors = jsonrpc_errors.JrErrors;

const messages = @import("../jsonrpc/messages.zig");


pub fn streamByDelimiter(alloc: Allocator, comptime delimiter: u8,
                         reader: anytype, buffered_writer: anytype,
                         dispatcher: anytype) !void {
    _=dispatcher;

    var line = std.ArrayList(u8).init(alloc);
    defer line.deinit();
    var buffered_reader = std.io.bufferedReader(reader);
    var buf_reader = buffered_reader.reader();
    var buf_writer = buffered_writer.writer();

    while (true) {
        line.clearRetainingCapacity();
        const read_count = buf_reader.streamUntilDelimiter(line.writer(), delimiter, null) catch |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        };
        _=read_count;

        try buf_writer.print("Line: {s}\n", .{line.items});
        try buffered_writer.flush();
    }
}


