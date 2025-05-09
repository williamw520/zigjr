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


pub fn nopLogger(_: []const u8, _: []const u8) void {
}

pub fn debugLogger(operation: []const u8, message: []const u8) void {
    std.debug.print("{s}: {s}\n", .{operation, message});
}


/// Provides frame level support for JSON-RPC streaming based on frame delimiters.
/// The framed request messages are delimited by the request_delimiter.
/// The framed response messages are delimited by the response_delimiter.
/// A typical JSON-RPC stream is delimited by '\n' (the CR character),
/// which reqires all message content not containing the character.
pub const DelimiterStream = struct {
    const Self = @This();

    alloc:              Allocator,
    request_delimiter:  u8,
    response_delimiter: u8,
    logger:             *const fn(operation: []const u8, message: []const u8) void,

    /// Initialize a stream struct.
    /// The logger param takes in a callback function to log the incoming and outgoing messages.
    pub fn init(alloc: Allocator, options: struct {
        request_delimiter: u8 = '\n',
        response_delimiter: u8 = '\n',
        logger: *const fn(operation: []const u8, message: []const u8) void = nopLogger,
    }) Self {
        return .{
            .alloc = alloc,
            .request_delimiter = options.request_delimiter,
            .response_delimiter = options.response_delimiter,
            .logger = options.logger,
        };
    }

    /// Runs a loop to read a stream of JSON request messages (frames) from the reader,
    /// handle each one with the dispatcher, and write the JSON responses to the buffered_writer.
    pub fn streamRequests(self: Self, reader: anytype, buf_writer: anytype, dispatcher: anytype) !void {
        var json_frame = std.ArrayList(u8).init(self.alloc);    // one frame is one JSON request.
        defer json_frame.deinit();
        var buf_reader = std.io.bufferedReader(reader);
        var json_reader = buf_reader.reader();
        var json_writer = buf_writer.writer();

        while (true) {
            json_frame.clearRetainingCapacity();
            _ = json_reader.streamUntilDelimiter(json_frame.writer(), self.request_delimiter, null) catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                }
            };

            self.logger("receive request", json_frame.items);
            if (try runner.runRequestJson(self.alloc, json_frame.items, dispatcher))|result_json| {
                try json_writer.writeAll(result_json);
                try json_writer.writeByte(self.response_delimiter);
                try buf_writer.flush();
                self.logger("return response", result_json);
                self.alloc.free(result_json);
            }
        }
    }

    /// Runs a loop to read a stream of JSON response messages (frames) from the reader,
    /// and handle each one with the dispatcher.
    pub fn streamResponses(self: Self, reader: anytype, dispatcher: anytype) !void {
        var json_frame = std.ArrayList(u8).init(self.alloc);    // one frame is one JSON response.
        defer json_frame.deinit();
        var buf_reader = std.io.bufferedReader(reader);
        var json_reader = buf_reader.reader();

        while (true) {
            json_frame.clearRetainingCapacity();
            _ = json_reader.streamUntilDelimiter(json_frame.writer(),
                                                 self.response_delimiter, null) catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                }
            };

            self.logger("receive response", json_frame.items);
            try runner.runResponseJson(self.alloc, json_frame.items, dispatcher);
        }
    }

};


/// Provides frame level support for JSON-RPC streaming based on Content-Length header.
/// The message frame has the format of:
///     Content-Length: MESSAGE_LENGTH\r\n
///     \r\n
///     JSON-RPC message
/// Each request message frame has a Content-Length header.
/// Each response message frame has a Content-Length header.
pub const ContentLengthStream = struct {
    const Self = @This();

    alloc:      Allocator,
    logger:     *const fn(operation: []const u8, message: []const u8) void,

    /// Initialize a stream struct.
    /// The logger param takes in a callback function to log the incoming and outgoing messages.
    pub fn init(alloc: Allocator, options: struct {
        logger: *const fn(operation: []const u8, message: []const u8) void = nopLogger,
    }) Self {
        return .{
            .alloc = alloc,
            .logger = options.logger,
        };
    }

    /// Runs a loop to read a stream of JSON request messages (frames) from the reader,
    /// handle each one with the dispatcher, and write the JSON responses to the buffered_writer.
    pub fn streamRequests(self: Self, reader: anytype, buf_writer: anytype, dispatcher: anytype) !void {
        var msg_buf = std.ArrayList(u8).init(self.alloc);
        defer msg_buf.deinit();
        var buf_reader = std.io.bufferedReader(reader);
        const json_reader = buf_reader.reader();
        const json_writer = buf_writer.writer();

        while (true) {
            const msg_len = frame.readContentLengthFrame(json_reader, &msg_buf) catch |err| {
                if (err == error.EndOfStream)
                    break;
                return err;
            };
            self.logger("receive request", msg_buf.items);
            if (msg_len == 0) continue;     // skip empty content frame.
            if (try runner.runRequestJson(self.alloc, msg_buf.items, dispatcher))|result_json| {
                try frame.writeContentLengthFrame(json_writer, result_json);
                try buf_writer.flush();
                self.logger("return response", result_json);
                self.alloc.free(result_json);
            }
        }
    }

    /// Runs a loop to read a stream of JSON response messages (frames) from the reader,
    /// and handle each one with the dispatcher.
    pub fn streamResponses(self: Self, reader: anytype, dispatcher: anytype) !void {
        var msg_buf = std.ArrayList(u8).init(self.alloc);
        defer msg_buf.deinit();
        var buf_reader = std.io.bufferedReader(reader);
        const json_reader = buf_reader.reader();

        while (true) {
            const msg_len = frame.readContentLengthFrame(json_reader, &msg_buf) catch |err| {
                if (err == error.EndOfStream)
                    break;
                return err;
            };
            self.logger("receive response", msg_buf.items);
            if (msg_len == 0) continue;     // skip empty content frame.
            try runner.runResponseJson(self.alloc, msg_buf.items, dispatcher);
        }
    }

};

