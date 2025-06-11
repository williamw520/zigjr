// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
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

const msg_handler = zigjr.msg_handler;
const JrErrors = zigjr.JrErrors;
const frame = @import("frame.zig");


/// Provides frame level support for JSON-RPC streaming based on frame delimiters.
/// The framed request messages are delimited by the options.request_delimiter.
/// The framed response messages will be delimited by the options.response_delimiter.
/// All messages should not contain the delimiter character.
/// A typical JSON-RPC stream is delimited by '\n' (the CR character).
pub const DelimiterStream = struct {
    const Self = @This();

    alloc:      Allocator,
    options:    DelimiterStreamOptions,

    /// Initialize a stream struct.
    /// The logger option takes in a callback function to log the incoming and outgoing messages.
    pub fn init(alloc: Allocator, options: DelimiterStreamOptions) Self {
        return .{
            .alloc = alloc,
            .options = options,
        };
    }

    /// Runs a loop to read a stream of JSON request messages (frames) from the reader,
    /// handle each one with the dispatcher, and write the JSON responses to the writer.
    pub fn streamRequests(self: Self, reader: anytype, writer: anytype, dispatcher: anytype) !void {
        var frame_buf = std.ArrayList(u8).init(self.alloc); // Each JSON request is a frame.
        defer frame_buf.deinit();
        const frame_writer = frame_buf.writer();
        var response_buf = std.ArrayList(u8).init(self.alloc);
        defer response_buf.deinit();
        const response_writer = response_buf.writer();
        var buffered_writer = std.io.bufferedWriter(writer);
        const output_writer = buffered_writer.writer();

        while (true) {
            frame_buf.clearRetainingCapacity();
            reader.streamUntilDelimiter(frame_writer, self.options.request_delimiter, null) catch |e| {
                switch (e) {
                    error.EndOfStream => break,
                    else => return e,   // unrecoverable error while reading from reader.
                }
            };

            const request_json = std.mem.trim(u8, frame_buf.items, " \t\r\n");
            if (self.options.skip_blank_message and request_json.len == 0) continue;

            self.options.logger("receive request", request_json);
            response_buf.clearRetainingCapacity();
            if (try msg_handler.handleJsonRequest(self.alloc, request_json, response_writer, dispatcher)) {
                try output_writer.writeAll(response_buf.items);
                try output_writer.writeByte(self.options.response_delimiter);
                try buffered_writer.flush();
                self.options.logger("return response", response_buf.items);
            }
        }
    }

    /// Runs a loop to read a stream of JSON response messages (frames) from the reader,
    /// and handle each one with the dispatcher.
    pub fn streamResponses(self: Self, reader: anytype, dispatcher: anytype) !void {
        var frame_buf = std.ArrayList(u8).init(self.alloc); // Each JSON response is one frame.
        defer frame_buf.deinit();
        const frame_writer = frame_buf.writer();

        while (true) {
            frame_buf.clearRetainingCapacity();
            reader.streamUntilDelimiter(frame_writer, self.options.response_delimiter, null) catch |e| {
                switch (e) {
                    error.EndOfStream => break,
                    else => return e,   // unrecoverable error while reading from reader.
                }
            };

            const response_json = std.mem.trim(u8, frame_buf.items, " \t\r\n");
            if (self.options.skip_blank_message and response_json.len == 0) continue;

            self.options.logger("receive response", response_json);
            msg_handler.handleJsonResponse(self.alloc, response_json, dispatcher) catch |err| {
                const stderr = std.io.getStdErr().writer();
                stderr.print("Error in handleJsonResponse(). {any}", .{err}) catch {};
            };
        }
    }

};

const DelimiterStreamOptions = struct {
    request_delimiter: u8 = '\n',
    response_delimiter: u8 = '\n',
    skip_blank_message: bool = true,
    logger: *const fn(operation: []const u8, message: []const u8) void = nopLogger,
};

/// A do-nothing logger that can be passed to the stream options.logger.
pub fn nopLogger(_: []const u8, _: []const u8) void {
}

/// A logger that logs to the std.debug.  It can be passed to the stream options.logger.
pub fn debugLogger(operation: []const u8, message: []const u8) void {
    std.debug.print("{s}: {s}\n", .{operation, message});
}


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
    options:    ContentLengthStreamOptions,

    /// Initialize a stream struct.
    /// The logger param takes in a callback function to log the incoming and outgoing messages.
    pub fn init(alloc: Allocator, options: ContentLengthStreamOptions) Self {
        return .{
            .alloc = alloc,
            .options = options,
        };
    }

    /// Runs a loop to read a stream of JSON request messages (frames) from the reader,
    /// handle each one with the dispatcher, and write the JSON responses to the buffered_writer.
    pub fn streamRequests(self: Self, reader: anytype, writer: anytype, dispatcher: anytype) !void {
        var frame_buf = std.ArrayList(u8).init(self.alloc);
        defer frame_buf.deinit();
        var response_buf = std.ArrayList(u8).init(self.alloc);
        defer response_buf.deinit();
        const response_writer = response_buf.writer();
        var buffered_writer = std.io.bufferedWriter(writer);
        const output_writer = buffered_writer.writer();

        while (true) {
            frame.readContentLengthFrame(reader, &frame_buf) catch |err| {
                switch (err) {
                    error.EndOfStream => return,
                    JrErrors.MissingContentLengthHeader => {
                        if (self.options.recover_on_missing_header) {
                            continue;
                        } else {
                            return err; // treat it as a unrecoverable error.
                        }
                    },
                    else => return err, // unrecoverable error while reading from reader.
                }
            };

            const request_json = std.mem.trim(u8, frame_buf.items, " \t");
            if (self.options.skip_blank_message and request_json.len == 0) continue;

            self.options.logger("receive request", request_json);
            response_buf.clearRetainingCapacity();
            if (try msg_handler.handleJsonRequest(self.alloc, request_json, response_writer, dispatcher)) {
                try frame.writeContentLengthFrame(output_writer, response_buf.items);
                try buffered_writer.flush();
                self.options.logger("return response", response_buf.items);
            }
        }
    }

    /// Runs a loop to read a stream of JSON response messages (frames) from the reader,
    /// and handle each one with the dispatcher.
    pub fn streamResponses(self: Self, reader: anytype, dispatcher: anytype) !void {
        var frame_buf = std.ArrayList(u8).init(self.alloc);
        defer frame_buf.deinit();

        while (true) {
            frame.readContentLengthFrame(reader, &frame_buf) catch |e| {
                switch (e) {
                    error.EndOfStream => break,
                    else => return e,   // unrecoverable error while reading from reader.
                }
            };

            const response_json = std.mem.trim(u8, frame_buf.items, " \t");
            if (self.options.skip_blank_message and response_json.len == 0) continue;

            self.options.logger("receive response", response_json);
            msg_handler.handleJsonResponse(self.alloc, response_json, dispatcher) catch |err| {
                const stderr = std.io.getStdErr().writer();
                stderr.print("Error in handleJsonResponse(). {any}", .{err}) catch {};
            };
        }
    }

};

pub const ContentLengthStreamOptions = struct {
    recover_on_missing_header: bool = true,
    skip_blank_message: bool = true,
    logger: *const fn(operation: []const u8, message: []const u8) void = nopLogger,
};


