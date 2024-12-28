const std = @import("std");

// const CharCombo = struct {
//     set: []u8,
//     counts: []u8,
// };

// pub fn readWordsFromFile(filename: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
//     const file = try std.fs.cwd().openFile(filename, .{});
//     defer file.close();
//     const file_size = try file.getEndPos();
//     const buffer = try allocator.alloc(u8, file_size);
//     defer allocator.free(buffer);
//     _ = try file.readAll(buffer);

//     var lines = std.mem.splitSequence(u8, buffer, "\n");
//     var word_list = std.ArrayList([]const u8).init(allocator);

//     while (lines.next()) |line| {
//         const trimmed = std.mem.trimRight(u8, line, " \r");
//         if (trimmed.len > 0) {
//             try word_list.append(trimmed);
//         }
//     }

//     return word_list.toOwnedSlice();
// }

// https://stackoverflow.com/a/77053872/8062159
pub fn readWordsFromFile(filename: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);
    var lines = std.mem.splitSequence(u8, buffer, "\n");
    var words = std.ArrayList([]const u8).init(allocator);
    while (lines.next()) |line| {
        const trimmed = std.mem.trimRight(u8, line, " \r");
        if (trimmed.len > 0) {
            try words.append(trimmed);
        }
    }
    return words.toOwnedSlice();
}

// pub fn readWordsFromFile(filename: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
//     var file = try std.fs.cwd().openFile(filename, .{});
//     defer file.close();
//     var buf_reader = std.io.bufferedReader(file.reader());
//     var in_stream = buf_reader.reader();
//     var words = std.ArrayList([]const u8).init(allocator);
//     var buf: [25]u8 = undefined;
//     while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
//         const trimmed = std.mem.trimRight(u8, line, " \r\n");
//         if (trimmed.len > 0) {
//             try words.append(trimmed);
//             // std.debug.print("{any} ", .{trimmed});
//             // std.debug.print("{any}\n", .{words});
//         }
//     }
//     return words.toOwnedSlice();
// }

// pub fn readWordsFromFile(filename: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
//     const file = try std.fs.cwd().openFile(filename, .{});
//     defer file.close();
//     var buffered = std.io.bufferedReader(file.reader());
//     const file_size = try file.getEndPos();
//     const buffer = try allocator.alloc(u8, file_size);
//     _ = try file.readAll(buffer);
//     var lines = std.mem.splitSequence(u8, buffer, "\n");
//     var words = std.ArrayList([]const u8).init(allocator);
//     while (lines.next()) |line| {
//         const trimmed = std.mem.trimRight(u8, line, " \r");
//         if (trimmed.len > 0) {
//             try words.append(trimmed);
//         }
//     }
//     return words.toOwnedSlice();
// }

//words -> combo word pairs -> filtered combo word pairs -> words grouped by combo
//[]string -> [](combo, string) -> [](combo, string) -> [](combo, []string)
//

const LetterCounts = struct {
    counts: [26]u8,
    set_len: u8,
};

pub fn getLetterCountsAndLen(word: []const u8) LetterCounts {
    // construct a 26 byte long array to store the number of each letter
    var counts = std.mem.zeroes([26]u8);
    // keep track of the number of unique letters
    var set_len: u8 = 0;

    for (word) |char| {
        switch (char) {
            'a'...'z' => { // transform lowercase
                const idx = char - 'a';
                if (counts[idx] == 0) {
                    set_len += 1;
                }
                counts[idx] += 1;
            },
            'A'...'Z' => { // transform uppercase
                const idx = char - 'A';
                if (counts[idx] == 0) {
                    set_len += 1;
                }
                counts[idx] += 1;
            },
            else => {}, // do nothing
        }
    }
    return LetterCounts{ .counts = counts, .set_len = set_len };
}

const LetterCombo = struct {
    counts: @Vector(26, u8),
    bits: u32,
};

// pub fn getLetterCombo(word: []const u8) LetterCombo {
//     // construct a 26 byte long array to store the number of each letter
//     var combo: LetterCombo = .{
//         .counts = std.mem.zeroes([26]u8),
//         .bits = 0
//     };
//     for (word) |char| {
//         switch (char) {
//             'a'...'z' => { // transform lowercase
//                 const idx = char - 'a';
//                 counts[idx] += 1;
//                 bits |= 1 << idx;
//             },
//             'A'...'Z' => { // transform uppercase
//                 const idx = char - 'A';
//                 counts[idx] += 1;
//                 bits |= 1 << idx;
//             },
//             else => {}, // do nothing
//         }
//     }
//     return combo;
// }


pub fn getLetterCounts(word: []const u8) @Vector(26, u8) {
    // construct a 26 byte long array to store the number of each letter
    var counts: @Vector(26, u8) = std.mem.zeroes([26]u8);
    for (word) |char| {
        switch (char) {
            'a'...'z' => { // transform lowercase
                counts[char - 'a'] += 1;
            },
            'A'...'Z' => { // transform uppercase
                counts[char - 'A'] += 1;
            },
            else => {}, // do nothing
        }
    }
    return counts;
}
// returns true if a can fit inside b
pub fn vec26_is_inside(a: [26]u8, b: [26]u8) bool {
    for (a, b) |ca, cb| {
        if (ca > cb) {
            return false;
        }
    }
    return true;
}

// pub fn getfilteredWordCombos(target_word: []const u8, words: [][]const u8, allocator: std.mem.Allocator) ![]ComboPair {
//     // _ = allocator;

//     const target_letter_counts = getLetterCounts(target_word);

//     // var pairs = [words.len]ComboPair;
//     var pairs = try allocator.alloc(ComboPair, words.len);
//     var pair_pos: usize = 0;

//     for (words) |word| {
//         const word_letter_counts = getLetterCounts(word);

//         // if word doesn't fit inside target then skip it
//         if (word_set_len > target_set_len or !vec26_is_inside(word_counts, target_counts)) {
//             continue;
//         }
//     }
//     return pairs[0..pair_pos];
// }

pub fn getFilteredWordComboPairs(target: []const u8, words: [][]const u8, allocator: std.mem.Allocator) ![]ComboPair  {
    const target_counts = getLetterCounts(target);
    var pairs: []ComboPair  = try allocator.alloc(ComboPair, words.len);
    // maybe just use arraylist for simplicity
    var size: usize = 0;
    for (words) |word| {
        const word_counts = getLetterCounts(word);
        // if word doesn't fit inside target then skip it
        if (@reduce(.Or, word_counts > target_counts )) {
            continue;
        }
        pairs[size] = .{ .combo = word_counts, .word = word };
        size += 1;
    }
    return pairs[0..size];
}

// pub fn getfilteredWordCombos(target_word: []const u8, words: [][]const u8, allocator: std.mem.Allocator) ![]ComboPair {
//     // _ = allocator;

//     const target_struct = getLetterCounts(target_word);
//     const target_counts = target_struct.counts;
//     const target_set_len = target_struct.set_len;

//     // var pairs = [words.len]ComboPair;
//     var pairs = try allocator.alloc(ComboPair, words.len);
//     var pair_pos: usize = 0;

//     for (words) |word| {
//         const word_struct = getLetterCounts(word);

//         const word_counts = word_struct.counts;
//         const word_set_len = word_struct.set_len;

//         // if word doesn't fit inside target then skip it
//         if (word_set_len > target_set_len or !vec26_is_inside(word_counts, target_counts)) {
//             continue;
//         }

//         // construct a pair containing an array of the letters and their counts
//         // and the word itself
//         var pair = ComboPair{ .combo = try allocator.alloc(CharCount, word_set_len) , .word = word };
//         var pos: u8 = 0;
//         for (word_counts, 0..) |count, char| {
//             if (count > 0) {
//                 pair.combo[pos] = CharCount{
//                     .char = @truncate(char),
//                     .count = count,
//                 };
//                 pos += 1;
//             }
//         }
//         pairs[pair_pos] = pair;
//         pair_pos += 1;
//     }
//     return pairs[0..pair_pos];
// }

const CharCount = struct {
    char: u8,
    count: u8,
};

const ComboPair = struct {
    combo: @Vector(26, u8),
    word: []const u8,
};

const ComboGroup = struct {
    key: []CharCount,
    words: [][]const u8,
};

const CharCombo = struct {
    set: []u8,
    counts: []u8,
};

// const CharCombo = struct {
//     set: []u8,
//     counts: []u8,
// };

const ComboVector = struct {
    counts: [26]u8,
    values: [26]u8,
};

// // update to binary search later
// pub fn find_idx(x: u8, a: CharCombo) u8 {
//     for (a.set, 0..) |y, idx| {
//         if (x == y) {
//             return idx;
//         }
//     }
//     return 255;
// }

// // do I want to pass a pointer instead of an actual CharCombo?
// pub fn is_subset(a: CharCombo, b: CountSet) bool {
//     for (a.set, a.counts) |char, count| {
//         const idx = find_idx(char, b);
//         if (idx == 255) {
//             return false;
//         }
//         if (count > b.counts[idx]) {
//             return false;
//         }
//     }
//     return true;
// }

// pub fn is_subset(a: CharCombo, b: [26]u8) bool {
//     for (a.set) |char| {
//         if (b[char - 97] == 0) {
//             return false;
//         }
//     }
// }

// pub fn get_combo_from_words(words: [][]u8) []ComboVector {
//     for (words) |w| {
//         std.debug.print(w);
//     }
// }

// pub fn combo_combos(target: CharCombo, combo_list: []CharCombo, result: std.ArrayList(CharCombo)) []CharCombo {
// }

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const words = try readWordsFromFile("/home/josh/.local/bin/words.txt", allocator);
    defer allocator.free(words);
    std.debug.print("{d}\n", .{words.len});
    const asdf = getLetterCounts("hello");
    std.debug.print("{any} ", .{asdf});
    const combos = try getFilteredWordComboPairs("hello", words, allocator);

    for (combos) |combo| {
        std.debug.print("{any} ", .{combo});
    }
}

test "read words" {
    const allocator = std.heap.page_allocator;
    const words = try readWordsFromFile("/home/josh/.local/bin/words.txt", allocator);
    defer allocator.free(words);
    for (words) |word| {
        std.debug.print("{s} ", .{word});
    }
    std.debug.print("\n{d}\n", .{words.len});
}
