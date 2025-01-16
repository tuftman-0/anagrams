const std = @import("std");

// https://stackoverflow.com/a/77053872/8062159
pub fn readWordsFromFile(filename: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    // defer allocator.free(buffer); // breaks everything because it frees too early
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

// words -> combo word pairs -> filtered combo word pairs -> words grouped by combo

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




// // old version
// pub fn printCombinations(
//     target: @Vector(26, u8),
//     wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
//     current_words: std.ArrayList([]const u8),
//     current_combo: std.ArrayList(@Vector(26, u8)),
//     start_index: usize,
//     allocator: std.mem.Allocator,
// ) !void {
//     const zero_vector: @Vector(26, u8) = @splat(0);
    
//     if (@reduce(.Or, target > zero_vector) == false) {
//         try printWordsForCurrentCombo(current_combo.items, 0, current_words, wordmap, allocator);
//         return;
//     }

//     const keys = wordmap.keys();

//     // std.sort.block([26]u8, keys[start_index..], {}, struct {
//     //     fn lessThan(_: void, a: [26]u8, b: [26]u8) bool {
//     //         var sum_a: u16 = 0;
//     //         var sum_b: u16 = 0;
//     //         for (a) |v| sum_a += v;
//     //         for (b) |v| sum_b += v;
//     //         return sum_b < sum_a; // reverse sort (descending)
//     //     }
//     // }.lessThan);
//     const remaining_keys = keys[start_index..];

//     for (remaining_keys, start_index..) |vec, i| {
//         if (@reduce(.Or, vec > target)) {
//             continue;
//         }

//         const remaining = target - vec;

//         var new_combo = try current_combo.clone();
//         try new_combo.append(vec);

//         try printCombinations(remaining, wordmap, current_words, new_combo, i, allocator);
//     }
// }


// // old
// fn printWordsForCurrentCombo(
//     combo: []const @Vector(26, u8),
//     index: usize,
//     current_words: std.ArrayList([]const u8),
//     wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
//     allocator: std.mem.Allocator,
// ) !void {
//     const stdout = std.io.getStdOut().writer();

//     if (index == combo.len) {
//         for (current_words.items) |word| {
//             try stdout.print("{s} ", .{word});
//         }
//         try stdout.writeAll("\n");
//         return;
//     }

//     if (wordmap.get(combo[index])) |words| {
//         for (words.items) |word| {
//             var new_words = try current_words.clone();
//             try new_words.append(word);
//             try printWordsForCurrentCombo(combo, index + 1, new_words, wordmap, allocator);
//         }
//     }
// }


// returns true if b can fit inside a
// pub fn is_inside(a: [26]u8) fn ([26]u8) bool {
//     const f = fn (b: [26]u8) bool {
//         return @reduce(.Or, b <= a)
//     };
//     return f;
// }

/// Filter a slice based on a predicate function, returning a new heap-allocated array
/// Caller owns the returned memory
pub fn filterSlice(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: []const T,
    pred: fn (T) bool,
) ![]T {
    var list = std.ArrayList(T).init(allocator);
    errdefer list.deinit();
    for (items) |item| {
        if (pred(item)) {
            try list.append(item);
        }
    }
    return try list.toOwnedSlice();
}


pub fn filterInside(
    allocator: std.mem.Allocator,
    // items: []@Vector(26, u8),
    items: [][26]u8,
    target: @Vector(26, u8),
) ![][26]u8 {
    var list = std.ArrayList([26]u8).init(allocator);
    errdefer list.deinit();
    for (items) |item| {
        if (@reduce(.Or, item <= target)) {
            try list.append(item);
        }
    }
    return try list.toOwnedSlice();
}
const Node = struct {
    vec: @Vector(26, u8),
    next: ?*Node,

    pub fn init(vec: @Vector(26, u8), next: ?*Node, allocator: std.mem.Allocator) !*Node {
        const node = try allocator.create(Node);
        node.* = .{ .vec = vec, .next = next };
        return node;
    }
};


pub fn printCombinations(
    target: @Vector(26, u8),
    remaining_combos: [][26]u8,
    current_combo: ?*Node,
    wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,
) !void {
    const zero_vector: @Vector(26, u8) = @splat(0);
    
    if (@reduce(.Or, target > zero_vector) == false) {
        try printWordsForCurrentCombo(current_combo, wordmap, allocator);
        return;
    }
    if (remaining_combos.len == 0) {
        return;
    }
    
    for (remaining_combos, 0..) |vec, i| {
        if (@reduce(.Or, vec > target)) {
            continue;
        }
        const remaining = target - vec;
        // const new_combos = filterSlice((, allocator: std.mem.Allocator, items: []const T, pred: fn(T)bool)
        const new_node = try Node.init(vec, current_combo, allocator);

        const filtered_combos = try filterInside(allocator, remaining_combos[i..], target);
        defer allocator.destroy(new_node);
        
        try printCombinations(remaining, filtered_combos, new_node, wordmap, allocator);
    }
}

fn printWordsForCurrentCombo(
    combo: ?*Node,
    wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,
) !void {
    const stdout = std.io.getStdOut().writer();

    if (combo == null) {
        try stdout.writeAll("\n");
        return;
    }

    // Convert vector back to array for hashmap lookup
    const vec_array: [26]u8 = combo.?.vec;
    if (wordmap.get(vec_array)) |words| {
        for (words.items) |word| {
            const new_node = combo.?.next;
            try stdout.print("{s} ", .{word});
            try printWordsForCurrentCombo(new_node, wordmap, allocator);
        }
    }
}


pub fn printAnagrams(input: []const u8, wordmap: std.AutoHashMap([26]u8, std.ArrayList([]const u8))) !void {
    _ = input;
    _ = wordmap;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Get command line args
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    // Get input either from args or stdin
    var input: []const u8 = undefined;
    var input_buf: [1024]u8 = undefined;

    if (args.next()) |arg| {
        // Use command line argument
        input = arg;
    } else {
        // Read from stdin
        const stdin = std.io.getStdIn();
        const bytes_read = try stdin.read(&input_buf);
        input = std.mem.trimRight(u8, input_buf[0..bytes_read], "\r\n");
    }

    const target = input;
    const target_combo = getLetterCounts(target);

    const words = try readWordsFromFile("/home/josh/.local/bin/words.txt", allocator);
    defer allocator.free(words);
    // std.debug.print("{d} words in wordlist\n", .{words.len});

    // std.debug.print("{any}: {s}\n", .{ target_combo, target });
    const pairs = try getFilteredWordComboPairs(target, words, allocator);
    defer allocator.free(pairs);

    // build hashmap
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

    // const initial_words = std.ArrayList([]const u8).init(allocator);

    // try printAllCombinations(target_combo, hashmap, initial_words, allocator);


    const vectors = hashmap.keys();
    try printCombinations(target_combo, vectors, null, hashmap, allocator);

    // const initial_combo = std.ArrayList(@Vector(26, u8)).init(allocator);
    // const initial_combo: ?*Node = null;
    // try printCombinations(target_combo, hashmap, initial_words, initial_combo, allocator);

    // var entries = hashmap.iterator();

    // while (entries.next()) |entry| {
    //     std.debug.print("{any}: {{ ", .{entry.key_ptr.*});
    //     defer std.debug.print("}}\n", .{});
    //     for (entry.value_ptr.*.items) |word| {
    //         std.debug.print("{s}, ", .{word});
    //     }
    // }

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
