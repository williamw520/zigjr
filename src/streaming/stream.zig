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

const runner = @import("../jsonrpc/runner.zig");
const frame = @import("frame.zig");


/// Provides framing level support for JSON-RPC streaming based on frame delimiter.
/// Runs a loop to read a stream of JSON request messages (frames) from the reader,
/// handle each one with the dispatcher, and write the JSON responses to the buffered_writer.
/// The incoming framed messages are delimitered by the read_delimiter.
/// The outgoing framed messages are delimitered by the write_delimiter.
/// A typical JSON-RPC stream is delimitered by '\n' the CR character,
/// which reqires all message content does not content the character.
pub fn delimiterRequestStream(alloc: Allocator, comptime read_delimiter: u8, comptime write_delimiter: u8,
                              reader: anytype, buffered_writer: anytype, dispatcher: anytype) !void {
    var json_frame = std.ArrayList(u8).init(alloc); // one frame is one JSON request.
    defer json_frame.deinit();
    var buffered_reader = std.io.bufferedReader(reader);
    var buf_reader = buffered_reader.reader();
    var buf_writer = buffered_writer.writer();

    while (true) {
        json_frame.clearRetainingCapacity();
        _ = buf_reader.streamUntilDelimiter(json_frame.writer(), read_delimiter, null) catch |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        };

        if (try runner.runRequestJson(alloc, json_frame.items, dispatcher))|result_json| {
            try buf_writer.print("{s}{c}", .{result_json, write_delimiter});
            try buffered_writer.flush();
            alloc.free(result_json);
        }
    }
}

/// Provides frame level support for JSON-RPC streaming based on Content-Length header.
/// The message frame has the format of:
///     Content-Length: MESSAGE_LENGTH\r\n
///     \r\n\r\n
///     JSON-RPC request message
/// Runs a loop to read a stream of JSON request messages (frames) from the reader,
/// handle each one with the dispatcher, and write the JSON responses to the buffered_writer.
/// Each incoming message frame from the reader has a Content-Length header.
/// Each outgoing message frame to the buffered_writer has a Content-Length header.
pub fn lengthRequestStream(alloc: Allocator, reader: anytype, buffered_writer: anytype,
                           dispatcher: anytype) !void {
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
        if (try runner.runRequestJson(alloc, msg_buf.items, dispatcher))|result_json| {
            try frame.writeContentLengthFrame(buf_writer, result_json);
            try buffered_writer.flush();
            alloc.free(result_json);
        }
    }
}


/// Provides framing level support for JSON-RPC streaming based on frame delimiter.
/// Runs a loop to read a stream of JSON response messages (frames) from the reader,
/// handle each one with the dispatcher.
/// The incoming framed messages are delimitered by the read_delimiter.
/// A typical JSON-RPC stream is delimitered by '\n' the CR character,
/// which reqires all message content does not content the character.
pub fn delimiterResponseStream(alloc: Allocator, comptime read_delimiter: u8,
                               reader: anytype, dispatcher: anytype) !void {
    var json_frame = std.ArrayList(u8).init(alloc); // one frame is one JSON response.
    defer json_frame.deinit();
    var buffered_reader = std.io.bufferedReader(reader);
    var buf_reader = buffered_reader.reader();

    while (true) {
        json_frame.clearRetainingCapacity();
        _ = buf_reader.streamUntilDelimiter(json_frame.writer(), read_delimiter, null) catch |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        };

        try runner.runResponseJson(alloc, json_frame.items, dispatcher);
    }
}

/// Provides frame level support for JSON-RPC streaming based on Content-Length header.
/// The message frame has the format of:
///     Content-Length: MESSAGE_LENGTH\r\n
///     \r\n\r\n
///     JSON-RPC response message
/// Runs a loop to read a stream of JSON response messages (frames) from the reader,
/// and handle each one with the dispatcher.
/// Each incoming message frame from the reader has a Content-Length header.
pub fn lengthResponseStream(alloc: Allocator, reader: anytype, dispatcher: anytype) !void {
    var msg_buf = std.ArrayList(u8).init(alloc);
    defer msg_buf.deinit();
    var buffered_reader = std.io.bufferedReader(reader);
    const buf_reader = buffered_reader.reader();

    while (true) {
        const msg_len = frame.readContentLengthFrame(buf_reader, &msg_buf) catch |err| {
            if (err == error.EndOfStream)
                break;
            return err;
        };
        if (msg_len == 0) continue;     // skip empty content frame.
        try runner.runResponseJson(alloc, msg_buf.items, dispatcher);
    }
}



