const std = @import("std");

const CharCombo = std.hash_map.HashMap(u8, usize);

fn fixWord(word: []const u8, allocator: *std.mem.Allocator) ![]const u8 {
    var result = try allocator.alloc(u8, word.len);
    var idx = 0;
    for (word) |c| {
        const lower = std.ascii.toLower(c);
        if (std.ascii.isLower(lower)) {
            result[idx] = lower;
            idx += 1;
        }
    }
    return result[0..idx];
}

fn countChars(word: []const u8, allocator: *std.mem.Allocator) !CharCombo {
    const fixedWord = try fixWord(word, allocator);
    var combo = CharCombo.init(allocator);
    defer combo.deinit();
    for (fixedWord) |c| {
        const entry = combo.put(c, 1);
        if (entry) |value| {
            value.* += 1;
        } else |err| {
            if (err != .OutOfMemory) return err;
        }
    }
    return combo;
}

fn contains(a: CharCombo, b: CharCombo) bool {
    for (b.entries()) |entry| {
        const key = entry.key;
        const value = entry.value;
        if (a.get(key)) |a_value| {
            if (a_value < value) return false;
        } else {
            return false;
        }
    }
    return true;
}

fn subtractMap(a: CharCombo, b: CharCombo, allocator: *std.mem.Allocator) !CharCombo {
    var result = CharCombo.init(allocator);
    defer result.deinit();
    for (a.entries()) |entry| {
        const key = entry.key;
        const a_value = entry.value;
        if (b.get(key)) |b_value| {
            if (a_value > b_value) {
                try result.put(key, a_value - b_value);
            }
        } else {
            try result.put(key, a_value);
        }
    }
    return result;
}

fn sortByLen(arr: []CharCombo, allocator: *std.mem.Allocator) ![]CharCombo {
    _ = allocator; // autofix
    // Sort the array by the sum of the values in each CharCombo in descending order
    const sorted = std.sort.sort(u8, arr, CharCombo.lessThan);
    return sorted;
}

fn comboCombos(target: CharCombo, wordlist: []CharCombo, combo: []CharCombo, allocator: *std.mem.Allocator) ![]CharCombo {
    if (target.size() == 0) {
        return combo;
    }
    if (wordlist.len == 0) {
        return combo;
    }

    const ntarget = try subtractMap(target, wordlist[0], allocator);
    const nws = wordlist[1..];
    const include = try comboCombos(ntarget, nws, &[_]CharCombo{wordlist[0]} ++ combo, allocator);
    const exclude = try comboCombos(target, nws, combo, allocator);

    return include ++ exclude;
}

fn anagrams(word: []const u8, wordlist: [][]const u8, allocator: *std.mem.Allocator) ![][]const u8 {
    const target = try countChars(word, allocator);
    defer target.deinit();

    var wordmap = std.hash_map.HashMap(CharCombo, [][]const u8).init(allocator);
    defer wordmap.deinit();

    for (wordlist) |w| {
        const combo = try countChars(w, allocator);
        if (contains(target, combo)) {
            if (wordmap.get(combo)) |list| {
                list.append(w) catch return error.OutOfMemory;
            } else {
                wordmap.put(combo, &[_][]const u8{w}) catch return error.OutOfMemory;
            }
        }
    }

    const keys = try wordmap.keys();
    const sorted_keys = try sortByLen(keys, allocator);

    const combos = try comboCombos(target, sorted_keys, &[_]CharCombo{}, allocator);
    var result = [][]const u8{};

    for (combos) |combo| {
        var words = [][]const u8{};
        for (combo) |key| {
            const list = wordmap.get(key) orelse return error.KeyNotFound;
            words.appendAll(list) catch return error.OutOfMemory;
        }
        result.append(words) catch return error.OutOfMemory;
    }
    return result;
}

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.heap.page_allocator.free(args);

    const allocator = std.heap.page_allocator;

    if (args.len == 2) {
        const wordfile = args[1];
        const word = args[2];
        const file = try std.fs.cwd().openFile(wordfile, .{ .mode = .read });
        const contents = try file.readToEndAlloc(allocator);
        defer allocator.free(contents);

        const words = std.mem.split(contents, " ");
        const result = try anagrams(word, words, allocator);

        for (result) |anagram| {
            std.debug.print("{s}\n", .{anagram});
        }
    } else {
        std.debug.print("Usage: anagrams <wordfile> <word>\n", .{});
    }
}
