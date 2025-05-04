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

const zigjr = @import("../zigjr.zig");
const JrErrors = zigjr.JrErrors;

const responder = @import("../jsonrpc/responder.zig");
const frame = @import("frame.zig");


/// Provides frame level support for JSON-RPC streaming based on Content-Length header.
/// The message frame has the format of:
///     Content-Length: MESSAGE_LENGTH\r\n
///     \r\n\r\n
///     JSON-RPC message
/// Runs a loop to read a stream of JSON request messages (frames) from the reader,
/// handle each one with the dispatcher, and write the JSON responses to the buffered_writer.
/// Each incoming message frame from the reader has a Content-Length header.
/// Each outgoing message frame to the write_delimiter has a Content-Length header.
pub fn streamByContentLength(alloc: Allocator, reader: anytype, buffered_writer: anytype, dispatcher: anytype) !void {
    var msg_buf = std.ArrayList(u8).init(alloc);
    defer msg_buf.deinit();
    var buffered_reader = std.io.bufferedReader(reader);
    const buf_reader = buffered_reader.reader();
    const buf_writer = buffered_writer.writer();

    while (true) {
        const msg_len = frame.readContentLengthFrame(buf_reader, &msg_buf) catch |err| {
            if (err == error.EndOfStream)
                break;
            return err;
        };
        if (msg_len == 0) continue;     // skip empty content frame.
        if (try responder.runJsonMessage(alloc, msg_buf.items, dispatcher))|result_json| {
            try frame.writeContentLengthFrame(buf_writer, result_json);
            try buffered_writer.flush();
            alloc.free(result_json);
        }
    }
}


