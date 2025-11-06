const Key = @import("vaxis").Key;

const Repl = @import("Repl.zig");

const Result = union(enum) {
    noop,
    done,
    hint: []const u8,
    exit: u8,
};

fn ctrlCombinations(repl: *Repl, key: Key) Result {
    if (!key.mods.ctrl) return .noop;

    const empty_input = repl.input.buf.buf.realLength() == 0;

    // Ctrl+D + empty input => exit
    if (key.codepoint == 'd') {
        if (empty_input) {
            return .{ .exit = 0 };
        }

        return .done;
    }

    // Ctrl+C => clear input
    if (key.codepoint == 'c') {
        if (!empty_input) {
            repl.input.buf.clearRetainingCapacity();
            return .done;
        }

        return .{ .hint = "Use Ctrl+D to exit" };
    }

    return .noop;
}

fn arrows(repl: *Repl, key: Key) Result {
    if (key.codepoint == Key.left) {
        if (key.mods.ctrl) {
            repl.input.buf.moveBackwardWordwise();
        } else {
            repl.input.buf.cursorLeft();
        }

        return .done;
    }

    if (key.codepoint == Key.right) {
        if (key.mods.ctrl) {
            repl.input.buf.moveForwardWordwise();
        } else {
            repl.input.buf.cursorRight();
        }

        return .done;
    }

    return .noop;
}

fn deletion(repl: *Repl, key: Key) Result {
    if (key.codepoint == Key.backspace) {
        if (key.mods.ctrl) {
            repl.input.buf.deleteWordBefore();
        } else {
            repl.input.buf.deleteBeforeCursor();
        }

        return .done;
    }

    if (key.codepoint == Key.delete) {
        if (key.mods.ctrl) {
            repl.input.buf.deleteWordAfter();
        } else {
            repl.input.buf.deleteAfterCursor();
        }

        return .done;
    }

    return .noop;
}

pub const handlers: []const *const fn (*Repl, Key) Result = &.{
    ctrlCombinations,
    arrows,
    deletion,
};
