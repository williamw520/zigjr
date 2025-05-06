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


/// Provides framing level support for JSON-RPC streaming based on frame delimiter.
/// Runs a loop to read a stream of JSON request messages (frames) from the reader,
/// handle each one with the dispatcher, and write the JSON responses to the buffered_writer.
/// The incoming framed messages are delimitered by the read_delimiter.
/// The outgoing framed messages are delimitered by the write_delimiter.
/// A typical JSON-RPC stream is delimitered by '\n' the CR character,
/// which reqires all message content does not content the character.
pub fn streamByDelimiter(alloc: Allocator, comptime read_delimiter: u8, comptime write_delimiter: u8,
                         reader: anytype, buffered_writer: anytype, dispatcher: anytype) !void {
    var frame = std.ArrayList(u8).init(alloc);  // one frame is one JSON request.
    defer frame.deinit();
    var buffered_reader = std.io.bufferedReader(reader);
    var buf_reader = buffered_reader.reader();
    var buf_writer = buffered_writer.writer();

    while (true) {
        frame.clearRetainingCapacity();
        _ = buf_reader.streamUntilDelimiter(frame.writer(), read_delimiter, null) catch |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        };

        if (try runner.runRequestJson(alloc, frame.items, dispatcher))|result_json| {
            try buf_writer.print("{s}{c}", .{result_json, write_delimiter});
            try buffered_writer.flush();
            alloc.free(result_json);
        }
    }
}


