// Toposort
// A Zig library for performing topological sort.
// Copyright (C) 2025 William Wong. All rights reserved.
// (williamw520@gmail.com)
//
// MIT License.  See the LICENSE file.
//

const std = @import("std");
const zigjr = @import("zigjr");
const Allocator = std.mem.Allocator;
const ParseOptions = std.json.ParseOptions;
const innerParse = std.json.innerParse;

const ArgIterator = std.process.ArgIterator;
const ArrayList = std.ArrayList;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const g_allocator = gpa.allocator();


test "test1" {

}

/// A command line tool that reads dependency data from file and
/// does topological sort using the Toposort library.
/// This serves as an example to exercise the Toposort library API.
pub fn main() !void {
    {
        var args = try CmdArgs.init(g_allocator);
        defer args.deinit();
        args.parse() catch |err| {
            std.debug.print("Error in parsing command arguments. {}\n", .{err});
            usage(args);
            return;
        };

        const data = read_file(args.msg_file) catch |err| {
            std.debug.print("Error in reading the message file. {}\n", .{err});
            usage(args);
            return;
        };
        defer g_allocator.free(data);

        var req_result = zigjr.parseRequest(g_allocator, data);
        defer req_result.deinit();
        std.debug.print("req: {any}\n", .{req_result.request()});

    }

    if (gpa.detectLeaks()) {
        std.debug.print("Memory leak detected!\n", .{});
    }    
}

fn read_file(data_file: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(data_file, .{ .mode = .read_only });
    defer file.close();
    const file_size = (try file.stat()).size;
    const file_data = file.readToEndAlloc(g_allocator, file_size);
    return file_data;
}

fn usage(args: CmdArgs) void {
    const program_name = std.fs.path.basename(args.program);
    std.debug.print(
        \\
        \\Usage:
        \\  {s} --msg data.json [--verbose]
        \\
        \\      --msg data.json  - read in the JSON-RPC 2.0 message file.
        \\      --verbose  - prints processing messages.
        \\
        , .{program_name});
}

// Poorman's quick and dirty command line argument parsing.
const CmdArgs = struct {
    const Self = @This();

    arg_itr:        ArgIterator,
    program:        []const u8,
    msg_file:       []const u8,

    fn init(allocator: Allocator) !CmdArgs {
        var args = CmdArgs {
            .arg_itr = try std.process.argsWithAllocator(allocator),
            .program = "",
            .msg_file = "data.json",   // default to data.json in the working dir.
        };
        var argv = args.arg_itr;
        args.program = argv.next() orelse "";
        return args;
    }

    fn parse(self: *Self) !void {
        var argv = self.arg_itr;
        while (argv.next())|argz| {
            const arg = std.mem.sliceTo(argz, 0);
            if (std.mem.eql(u8, arg, "--msg")) {
                self.msg_file = std.mem.sliceTo(argv.next(), 0) orelse "data.json";
            }
        }
    }

    fn deinit(self: *CmdArgs) void {
        self.arg_itr.deinit();
    }

};


