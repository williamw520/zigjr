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

// const msg_handler = @import("../rpc/msg_handler.zig");
// const RequestDispatcher = msg_handler.RequestDispatcher;
const RequestDispatcher = @import("../rpc/dispatcher.zig").RequestDispatcher;
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
    /// The writer is buffered internally.  The reader is not buffered.
    /// Caller might want to wrap a buffered reader around it.
    pub fn streamRequests(self: Self, reader: anytype, writer: anytype, dispatcher: RequestDispatcher) !void {
        var frame_buf = std.ArrayList(u8).init(self.alloc); // Each JSON request is a frame.
        defer frame_buf.deinit();
        const frame_writer = frame_buf.writer();
        var response_buf = std.ArrayList(u8).init(self.alloc);
        defer response_buf.deinit();
        const response_writer = response_buf.writer();
        var buffered_writer = std.io.bufferedWriter(writer);
        const output_writer = buffered_writer.writer();

        self.options.logger.start("[streamRequests] Logging starts");
        defer { self.options.logger.stop("[streamRequests] Logging stops"); }

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

            self.options.logger.log("streamRequests", "receive request", request_json);
            response_buf.clearRetainingCapacity();
            if (try zigjr.handleJsonRequest(self.alloc, request_json, response_writer, dispatcher)) {
                try output_writer.writeAll(response_buf.items);
                try output_writer.writeByte(self.options.response_delimiter);
                try buffered_writer.flush();
                self.options.logger.log("streamRequests", "return response", response_buf.items);
            }
        }
    }

    /// Runs a loop to read a stream of JSON response messages (frames) from the reader,
    /// and handle each one with the dispatcher.
    pub fn streamResponses(self: Self, reader: anytype, dispatcher: anytype) !void {
        var frame_buf = std.ArrayList(u8).init(self.alloc); // Each JSON response is one frame.
        defer frame_buf.deinit();
        const frame_writer = frame_buf.writer();

        self.options.logger.start("[streamResponses] Logging starts");
        defer { self.options.logger.stop("[streamResponses] Logging stops"); }

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

            self.options.logger.log("streamResponses", "receive response", response_json);
            zigjr.handleJsonResponse(self.alloc, response_json, dispatcher) catch |err| {
                const stderr = std.io.getStdErr().writer();
                stderr.print("Error in handleJsonResponse(). {any}", .{err}) catch {};
            };
        }
    }

};

pub const DelimiterStreamOptions = struct {
    request_delimiter: u8 = '\n',
    response_delimiter: u8 = '\n',
    skip_blank_message: bool = true,
    logger: Logger = Logger.impl_by(&nopLogger),
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
    pub fn streamRequests(self: Self, reader: anytype, writer: anytype, dispatcher: RequestDispatcher) !void {
        var frame_buf = std.ArrayList(u8).init(self.alloc);
        defer frame_buf.deinit();
        var response_buf = std.ArrayList(u8).init(self.alloc);
        defer response_buf.deinit();
        const response_writer = response_buf.writer();
        var buffered_writer = std.io.bufferedWriter(writer);
        const output_writer = buffered_writer.writer();

        self.options.logger.start("[streamRequests] Logging starts");
        defer { self.options.logger.stop("[streamRequests] Logging stops"); }

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

            self.options.logger.log("streamRequests", "receive request", request_json);
            response_buf.clearRetainingCapacity();
            if (try zigjr.handleJsonRequest(self.alloc, request_json, response_writer, dispatcher)) {
                try frame.writeContentLengthFrame(output_writer, response_buf.items);
                try buffered_writer.flush();
                self.options.logger.log("streamRequests", "return response", response_buf.items);
            }
        }
    }

    /// Runs a loop to read a stream of JSON response messages (frames) from the reader,
    /// and handle each one with the dispatcher.
    pub fn streamResponses(self: Self, reader: anytype, dispatcher: anytype) !void {
        var frame_buf = std.ArrayList(u8).init(self.alloc);
        defer frame_buf.deinit();

        self.options.logger.start("[streamResponses] Logging starts");
        defer { self.options.logger.stop("[streamResponses] Logging stops"); }

        while (true) {
            frame.readContentLengthFrame(reader, &frame_buf) catch |e| {
                switch (e) {
                    error.EndOfStream => break,
                    else => return e,   // unrecoverable error while reading from reader.
                }
            };

            const response_json = std.mem.trim(u8, frame_buf.items, " \t");
            if (self.options.skip_blank_message and response_json.len == 0) continue;

            self.options.logger.log("streamResponses", "receive response", response_json);
            zigjr.handleJsonResponse(self.alloc, response_json, dispatcher) catch |err| {
                const stderr = std.io.getStdErr().writer();
                stderr.print("Error in handleJsonResponse(). {any}", .{err}) catch {};
            };
        }
    }

};

pub const ContentLengthStreamOptions = struct {
    recover_on_missing_header: bool = true,
    skip_blank_message: bool = true,
    logger: Logger = Logger.impl_by(&nopLogger),
};


/// Logger interface
pub const Logger = struct {
    impl_ptr:   *anyopaque,
    start_fn:   *const fn(impl_ptr: *anyopaque, message: []const u8) void,
    log_fn:     *const fn(impl_ptr: *anyopaque, source: [] const u8, operation: []const u8, message: []const u8) void,
    stop_fn:    *const fn(impl_ptr: *anyopaque, message: []const u8) void,

    // Interface is implemented by the 'impl' object.
    pub fn impl_by(impl: anytype) Logger {
        const ImplType = @TypeOf(impl);

        const Thunk = struct {
            fn start(impl_ptr: *anyopaque, message: []const u8) void {
                const implementation: ImplType = @ptrCast(@alignCast(impl_ptr));
                implementation.start(message);
            }

            fn log(impl_ptr: *anyopaque, source: [] const u8, operation: []const u8, message: []const u8) void {
                const implementation: ImplType = @ptrCast(@alignCast(impl_ptr));
                implementation.log(source, operation, message);
            }

            fn stop(impl_ptr: *anyopaque, message: []const u8) void {
                const implementation: ImplType = @ptrCast(@alignCast(impl_ptr));
                implementation.stop(message);
            }
        };

        return .{
            .impl_ptr = impl,
            .start_fn = Thunk.start,
            .log_fn = Thunk.log,
            .stop_fn = Thunk.stop,
        };
    }

    fn start(self: @This(), message: []const u8) void {
        self.start_fn(self.impl_ptr, message);
    }

    fn log(self: @This(), source: [] const u8, operation: []const u8, message: []const u8) void {
        self.log_fn(self.impl_ptr, source, operation, message);
    }

    fn stop(self: @This(), message: []const u8) void {
        self.stop_fn(self.impl_ptr, message);
    }

};


/// A nop logger that implements the Logger interface; can be passed to the stream options.logger.
pub const NopLogger = struct {
    pub fn start(_: @This(), _: []const u8) void {}
    pub fn log(_: @This(), _: []const u8, _: []const u8, _: []const u8) void {}
    pub fn stop(_: @This(), _: []const u8) void {}
};

var nopLogger = NopLogger{};


/// A logger that prints to std.dbg, implemented the Logger interface.
pub const DbgLogger = struct {
    pub fn start(_: *@This(), message: []const u8) void {
        std.debug.print("{s}\n", .{message});
    }

    pub fn log(_: *@This(), source: []const u8, operation: []const u8, message: []const u8) void {
        std.debug.print("[{s}] {s} - {s}\n", .{source, operation, message});
    }

    pub fn stop(_: *@This(), message: []const u8) void {
        std.debug.print("{s}\n", .{message});
    }
};


/// A logger that logs to file, implemented the Logger interface.
pub const FileLogger = struct {
    count: usize = 0,
    file: std.fs.File,
    writer: std.fs.File.Writer,

    pub fn init(file_path: []const u8) !FileLogger {
        const file = try fileOpenIf(file_path);
        try file.seekFromEnd(0);    // seek to end for appending to file.
        return .{
            .file = file,
            .writer = file.writer(),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.file.close();
    }

    pub fn start(self: *@This(), message: []const u8) void {
        const ts_sec = std.time.timestamp();
        self.writer.print("Timestamp {d} - {s}\n", .{ts_sec, message})
            catch |err| std.debug.print("Error while printing in start(). {any}\n", .{err});
    }

    pub fn log(self: *@This(), source: []const u8, operation: []const u8, message: []const u8) void {
        self.count += 1;
        self.writer.print("{}: [{s}] {s} - {s}\n", .{self.count, source, operation, message})
            catch |err| std.debug.print("Error while printing in log(). {any}\n", .{err});
    }
    
    pub fn stop(self: *@This(), message: []const u8) void {
        const ts_sec = std.time.timestamp();
        self.writer.print("Timestamp {d} - {s}\n\n", .{ts_sec, message})
            catch |err| std.debug.print("Error while printing in stop(). {any}\n", .{err});
    }

    fn fileOpenIf(file_path: []const u8) !std.fs.File {
        return std.fs.cwd().openFile(file_path, .{ .mode = .write_only }) catch |err| {
            if (err == error.FileNotFound) {
                return try std.fs.cwd().createFile(file_path, .{ .read = false });
            } else {
                return err;
            }
        };
    }
    
};


