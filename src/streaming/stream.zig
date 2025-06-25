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

const RequestDispatcher = zigjr.RequestDispatcher;
const ResponseDispatcher = zigjr.ResponseDispatcher;
const JrErrors = zigjr.JrErrors;
const frame = @import("frame.zig");



/// Runs a loop to read a stream of JSON request messages (frames) from the reader,
/// handle each one with the dispatcher, and write the JSON responses to the writer.
/// The writer is buffered internally.  The reader is not buffered.
/// Caller might want to wrap a buffered reader around it.
pub fn requestsByDelimiter(alloc: Allocator, reader: anytype, writer: anytype,
                           dispatcher: RequestDispatcher, options: DelimiterOptions) !void {
    var frame_buf = std.ArrayList(u8).init(alloc); // Each JSON request is a frame.
    defer frame_buf.deinit();
    const frame_writer = frame_buf.writer();
    var response_buf = std.ArrayList(u8).init(alloc);
    defer response_buf.deinit();
    // const response_writer = response_buf.writer();
    var buffered_writer = std.io.bufferedWriter(writer);
    const output_writer = buffered_writer.writer();
    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
    defer pipeline.deinit();

    options.logger.start("[requestsByDelimiter] Logging starts");
    defer { options.logger.stop("[requestsByDelimiter] Logging stops"); }

    while (true) {
        frame_buf.clearRetainingCapacity();
        reader.streamUntilDelimiter(frame_writer, options.request_delimiter, null) catch |e| {
            switch (e) {
                error.EndOfStream => break,
                else => return e,   // unrecoverable error while reading from reader.
            }
        };

        const request_json = std.mem.trim(u8, frame_buf.items, " \t\r\n");
        if (options.skip_blank_message and request_json.len == 0) continue;

        options.logger.log("requestsByDelimiter", "receive request", request_json);
        // response_buf.clearRetainingCapacity();
        if (try pipeline.runRequest(request_json, &response_buf)) {
            try output_writer.writeAll(response_buf.items);
            try output_writer.writeByte(options.response_delimiter);
            try buffered_writer.flush();
            options.logger.log("requestsByDelimiter", "return response", response_buf.items);
        }
    }
}


// Runs a loop to read a stream of JSON response messages (frames) from the reader,
// and handle each one with the dispatcher.
pub fn responsesByDelimiter(alloc: Allocator, reader: anytype,
                            dispatcher: ResponseDispatcher, options: DelimiterOptions) !void {
    var frame_buf = std.ArrayList(u8).init(alloc);  // Each JSON response is one frame.
    defer frame_buf.deinit();
    const frame_writer = frame_buf.writer();
    const pipeline = zigjr.ResponsePipeline.init(alloc, dispatcher);

    options.logger.start("[streamResponses] Logging starts");
    defer { options.logger.stop("[streamResponses] Logging stops"); }

    while (true) {
        frame_buf.clearRetainingCapacity();
        reader.streamUntilDelimiter(frame_writer, options.response_delimiter, null) catch |e| {
            switch (e) {
                error.EndOfStream => break,
                else => return e,   // unrecoverable error while reading from reader.
            }
        };

        const response_json = std.mem.trim(u8, frame_buf.items, " \t\r\n");
        if (options.skip_blank_message and response_json.len == 0) continue;

        options.logger.log("streamResponses", "receive response", response_json);
        pipeline.handleJsonResponse(response_json) catch |err| {
            const stderr = std.io.getStdErr().writer();
            stderr.print("Error in handleJsonResponse(). {any}", .{err}) catch {};
        };
    }
}

pub const DelimiterOptions = struct {
    request_delimiter: u8 = '\n',
    response_delimiter: u8 = '\n',
    skip_blank_message: bool = true,
    logger: zigjr.Logger = zigjr.Logger.implBy(&nopLogger),
};


/// Runs a loop to read a stream of JSON request messages (frames) from the reader,
/// handle each one with the dispatcher, and write the JSON responses to the buffered_writer.
pub fn requestsByContentLength(alloc: Allocator, reader: anytype, writer: anytype,
                               dispatcher: RequestDispatcher, options: ContentLengthOptions) !void {
    var frame_buf = std.ArrayList(u8).init(alloc);
    defer frame_buf.deinit();
    var response_buf = std.ArrayList(u8).init(alloc);
    defer response_buf.deinit();
    // const response_writer = response_buf.writer();
    var buffered_writer = std.io.bufferedWriter(writer);
    const output_writer = buffered_writer.writer();
    var pipeline = zigjr.RequestPipeline.init(alloc, dispatcher, null);
    defer pipeline.deinit();

    options.logger.start("[requestsByContentLength] Logging starts");
    defer { options.logger.stop("[requestsByContentLength] Logging stops"); }

    while (true) {
        frame.readContentLengthFrame(reader, &frame_buf) catch |err| {
            switch (err) {
                error.EndOfStream => return,
                JrErrors.MissingContentLengthHeader => {
                    if (options.recover_on_missing_header) {
                        continue;
                    } else {
                        return err; // treat it as a unrecoverable error.
                    }
                },
                else => return err, // unrecoverable error while reading from reader.
            }
        };

        const request_json = std.mem.trim(u8, frame_buf.items, " \t");
        if (options.skip_blank_message and request_json.len == 0) continue;

        options.logger.log("requestsByContentLength", "receive request", request_json);
        // response_buf.clearRetainingCapacity();
        if (try pipeline.runRequest(request_json, &response_buf)) {
            try frame.writeContentLengthFrame(output_writer, response_buf.items);
            try buffered_writer.flush();
            options.logger.log("requestsByContentLength", "return response", response_buf.items);
        }
    }
}

/// Runs a loop to read a stream of JSON response messages (frames) from the reader,
/// and handle each one with the dispatcher.
pub fn responsesByContentLength(alloc: Allocator, reader: anytype,
                                dispatcher: ResponseDispatcher, options: ContentLengthOptions) !void {
    var frame_buf = std.ArrayList(u8).init(alloc);
    defer frame_buf.deinit();
    const pipeline = zigjr.ResponsePipeline.init(alloc, dispatcher);

    options.logger.start("[streamResponses] Logging starts");
    defer { options.logger.stop("[streamResponses] Logging stops"); }

    while (true) {
        frame.readContentLengthFrame(reader, &frame_buf) catch |e| {
            switch (e) {
                error.EndOfStream => break,
                else => return e,   // unrecoverable error while reading from reader.
            }
        };

        const response_json = std.mem.trim(u8, frame_buf.items, " \t");
        if (options.skip_blank_message and response_json.len == 0) continue;

        options.logger.log("streamResponses", "receive response", response_json);
        pipeline.handleJsonResponse(response_json) catch |err| {
            const stderr = std.io.getStdErr().writer();
            stderr.print("Error in handleJsonResponse(). {any}", .{err}) catch {};
        };
    }
}

pub const ContentLengthOptions = struct {
    recover_on_missing_header: bool = true,
    skip_blank_message: bool = true,
    logger: zigjr.Logger = zigjr.Logger.implBy(&nopLogger),
};

var nopLogger = zigjr.NopLogger{};


