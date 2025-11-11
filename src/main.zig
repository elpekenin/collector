const std = @import("std");

const zmig = @import("zmig");

const commands = @import("commands.zig");
const database = @import("database.zig");
const utils = @import("utils.zig");

const App = @import("App.zig");
const Repl = @import("Repl.zig");

fn validArgs(allocator: std.mem.Allocator) !bool {
    var args: std.process.ArgIterator = try .initWithAllocator(allocator);
    defer args.deinit();

    if (!args.skip()) return false;
    if (args.skip()) return false;
    return true;
}

fn createDirectory(allocator: std.mem.Allocator, dir_path: []const u8) !bool {
    const absolute_path = try std.fs.path.resolve(allocator, &.{dir_path});
    defer allocator.free(absolute_path);

    std.fs.accessAbsolute(absolute_path, .{}) catch |e| switch (e) {
        error.FileNotFound => {
            try std.fs.makeDirAbsolute(absolute_path);
            return true;
        },
        else => return e,
    };

    return false;
}

pub fn main() !u8 {
    var stdout_fw: std.fs.File.Writer = .init(.stdout(), &.{});
    const stdout = &stdout_fw.interface;

    var stderr_fw: std.fs.File.Writer = .init(.stderr(), &.{});
    const stderr = &stderr_fw.interface;

    // TODO: find some other (faster) allocator to use
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    if (!try validArgs(allocator)) {
        try stderr.print("program doesn't receive any arguments\n", .{});
        return 1;
    }

    const dir_path = try std.fs.getAppDataDir(allocator, "collector");
    defer allocator.free(dir_path);

    if (try createDirectory(allocator, dir_path)) {
        try stdout.print("info: created '{s}' for data storage\n", .{dir_path});
    }

    const path = try std.fs.path.joinZ(allocator, &.{ dir_path, "db.sqlite3" });
    defer allocator.free(path);

    var diagnostics: zmig.Diagnostics = undefined;
    var db = database.init(allocator, path, &diagnostics) catch {
        try stderr.print("could not connect to database: {f}\n", .{diagnostics});
        return 1;
    };
    defer db.deinit();

    var app: App = .{
        .allocator = allocator,
        .connection = db,
        .exitcode = 0,
        .repl = .create(allocator),
        .stderr = stderr,
        .stdout = stdout,
        .stop = false,
    };

    try app.repl.init(&.{});
    defer app.repl.deinit();

    return innerMain(&app);
}

const Command = enum {
    db, // display path of sqlite file
    download, // download info from API into DB
    exit, // end program
    help, // list available commands

    // manage owned cards
    add,
    rm,

    // show owned cards
    missing,
    owned,
};

fn innerMain(app: *App) !u8 {
    while (!app.stop) {
        try app.repl.render();

        const event = try app.repl.nextEvent() orelse continue;

        const user_input = switch (event) {
            .exit => |code| return code,
            .input => |input| input,
        };

        // make sure not to leak the received slice
        defer app.repl.allocator.free(user_input);

        // store current input, so that it shows up the screen later
        try app.repl.storeInput(user_input);

        var r: std.Io.Reader = .fixed(user_input);
        const reader = &r;

        // nothing to do on empty input
        const str = try utils.takeWord(reader) orelse {
            try app.repl.promptInNewLine();
            continue;
        };

        const command = std.meta.stringToEnum(Command, str) orelse {
            try app.repl.err(&.{ "unknown command: ", str }, .{});
            continue;
        };

        switch (command) {
            .db => try commands.db(app, reader),
            .download => try commands.download(app, reader),
            .exit => try commands.exit(app, reader),
            .help => try commands.help(Command, app, reader),
            .add, .rm => try commands.row(app, reader, command == .add),
            .missing, .owned => try commands.list(app, reader, command == .owned),
        }
    }

    return app.exitcode;
}
