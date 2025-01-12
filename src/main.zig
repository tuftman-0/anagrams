const std = @import("std");

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

//words -> combo word pairs -> filtered combo word pairs -> words grouped by combo
//[]string -> [](combo, string) -> [](combo, string) -> [](combo, []string)
//

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

pub fn getFilteredWordComboPairs(target: []const u8, words: [][]const u8, allocator: std.mem.Allocator) ![]ComboPair {
    const target_counts = getLetterCounts(target);
    var pairs: []ComboPair = try allocator.alloc(ComboPair, words.len);
    // maybe just use arraylist for simplicity
    var size: usize = 0;
    for (words) |word| {
        const word_counts = getLetterCounts(word);
        // if word doesn't fit inside target then skip it
        if (@reduce(.Or, word_counts > target_counts)) {
            continue;
        }
        pairs[size] = .{ .combo = word_counts, .word = word };
        size += 1;
    }
    _ = allocator.resize(pairs, size);
    return pairs[0..size];
}

const ComboPair = struct {
    combo: @Vector(26, u8),
    word: []const u8,
};

// pub fn makeHashMap(comboPairs: []ComboPair) std.AutoHashMap([26]u8, std.ArrayList([]const u8)) {  }

// pub fn get_combo_from_words(words: [][]u8) []ComboVector {
//     for (words) |w| {
//         std.debug.print(w);
//     }
// }

// pub fn comboCombos(target: @Vector(26, u8) , combo_list: []@Vector(26, u8), result: std.ArrayList(@Vector(26, u8))) [][]@Vector(26, u8) {
//     return result;
// }



// TODO
// figure out type of wordmap input
// figure out how ta
// make/find cartesian product function
// 

pub fn printAnagrams(input: []const u8, wordmap: std.AutoHashMap([26]u8, std.ArrayList([]const u8))) !void {
    _ = input;
    _ = wordmap;
}

pub fn main() !void {
    // const allocator = std.heap.page_allocator;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const words = try readWordsFromFile("/home/josh/.local/bin/words.txt", allocator);
    defer allocator.free(words);
    std.debug.print("{d} words in wordlist\n", .{words.len});

    // const target = "floorp";
    const target = "abracadabramonkeybutt";
    const target_combo = getLetterCounts(target);


    std.debug.print("{any}: {s}\n", .{target_combo, target});
    const pairs = try getFilteredWordComboPairs(target, words, allocator);
    defer allocator.free(pairs);

    var hashmap = std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)).init(allocator);
    for (pairs) |pair| {
        const found = hashmap.getPtr(pair.combo);
        if (found) |*list| {
            try list.*.append(pair.word);
        } else {
            var list = std.ArrayList([]const u8).init(allocator);
            try list.append(pair.word);
            try hashmap.put(pair.combo, list);
        }
    }

    var entries = hashmap.iterator();


    while (entries.next()) |entry| {
        std.debug.print("{any}: {{ ", .{entry.key_ptr.*});
        defer std.debug.print("}}\n", .{});
        for (entry.value_ptr.*.items) |word| {
            std.debug.print("{s}, ", .{word});
        }
    }

    // for (pairs) |pair| {
    //     // std.debug.print("{any} ", .{combo});
    //     std.debug.print("{any}: {s}\n", pair);
    // }
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
