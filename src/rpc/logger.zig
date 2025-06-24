// Zig JR
// A Zig based JSON-RPC 2.0 library.
// Copyright (C) 2025 William W. Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");


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

    // The implementation must have methods.

    pub fn start(self: @This(), message: []const u8) void {
        self.start_fn(self.impl_ptr, message);
    }

    pub fn log(self: @This(), source: [] const u8, operation: []const u8, message: []const u8) void {
        self.log_fn(self.impl_ptr, source, operation, message);
    }

    pub fn stop(self: @This(), message: []const u8) void {
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


