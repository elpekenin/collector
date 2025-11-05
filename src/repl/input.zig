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

    const empty_input = repl.text.buf.realLength() == 0;

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
            repl.text.clearRetainingCapacity();
            return .done;
        }

        return .{ .hint = "Use Ctrl+D to exit" };
    }

    return .noop;
}

fn arrows(repl: *Repl, key: Key) Result {
    if (key.codepoint == Key.left) {
        if (key.mods.ctrl) {
            repl.text.moveBackwardWordwise();
        } else {
            repl.text.cursorLeft();
        }

        return .done;
    }

    if (key.codepoint == Key.right) {
        if (key.mods.ctrl) {
            repl.text.moveForwardWordwise();
        } else {
            repl.text.cursorRight();
        }

        return .done;
    }

    return .noop;
}

fn deletion(repl: *Repl, key: Key) Result {
    if (key.codepoint == Key.backspace) {
        if (key.mods.ctrl) {
            repl.text.deleteWordBefore();
        } else {
            repl.text.deleteBeforeCursor();
        }

        return .done;
    }

    if (key.codepoint == Key.delete) {
        if (key.mods.ctrl) {
            repl.text.deleteWordAfter();
        } else {
            repl.text.deleteAfterCursor();
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
