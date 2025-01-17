const std = @import("std");
const stdout = std.io.getStdOut().writer();

// https://stackoverflow.com/a/77053872/8062159
//
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


/// Caller owns the returned memory
pub fn filterInside(
    allocator: std.mem.Allocator,
    // items: []@Vector(26, u8),
    items: [][26]u8,
    target: @Vector(26, u8),
) ![][26]u8 {
    var list = std.ArrayList([26]u8).init(allocator);
    errdefer list.deinit();
    for (items) |item| {
        if (@reduce(.And, item <= target)) {
            try list.append(item);
        }
    }
    return try list.toOwnedSlice();
}

const Node = struct {
    // vec: @Vector(26, u8),
    vec: [26]u8,
    next: ?*Node,

    pub fn init(vec: [26]u8, next: ?*Node, allocator: std.mem.Allocator) !*Node {
        const node = try allocator.create(Node);
        node.* = .{ .vec = vec, .next = next };
        return node;
    }
};


  
// pub fn reverseList(node: ?*Node, allocator: std.mem.Allocator) ?*Node {
//     if (node == null) {
//         return null;
//     }
//     const new_tail = Node.init(node.?.vec, null, allocator);
//     return Node.init(reverseList(node.?.next, allocator), new_tail, allocator);
// }

pub fn printVec(vec: [26]u8) void {
    const alpha = "abcdefghijklmnopqrstuvwxyz";
    for (vec, 0..) |n,i| {
        if (n != 0) {
            std.debug.print("{c}{d}" , .{alpha[i], n});
        }
        // var x = n;
        // while (x > 0) : (x -= 1) {
        //     std.debug.print("{c}" , .{alpha[i]});
        // }
    }
}

pub fn printCombinations(
    target: @Vector(26, u8),
    remaining_combos: [][26]u8,
    current_combo: ?*Node,
    wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,
) !void {
    const zero_vector: @Vector(26, u8) = @splat(0);

    if (@reduce(.And, target == zero_vector)) {
        try printWordsForCurrentCombo(current_combo, wordmap, allocator);
        return;
    }

    for (remaining_combos, 0..) |vec, i| {
        const remaining = target - vec;
        const new_node = try Node.init(vec, current_combo, allocator);
        defer allocator.destroy(new_node);

        const filtered_combos = try filterInside(allocator, remaining_combos[i..], remaining);
        defer allocator.free(filtered_combos);

        try printCombinations(remaining, filtered_combos, new_node, wordmap, allocator);
    }
}

fn printWordsForCurrentCombo(
    combo: ?*Node,
    wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,
) !void {
    if (combo == null) {
        try stdout.writeAll("\n");
        // try stdout.print("\n", .{});
        return;
    }

    if (wordmap.get(combo.?.vec)) |words| {
        const next_combo = combo.?.next;
        for (words.items) |word| {
            try printWordsForCurrentCombo(next_combo, wordmap, allocator);
            try stdout.print("{s} ", .{word});
        }
    } else {
        std.debug.print("ERR", .{});
    }
}



// //this is stupid but the main recursive version didn't work so I'm trying this instead
// fn printWordsForCurrentCombo(
//     combo: ?*Node,
//     wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
//     allocator: std.mem.Allocator,
// ) !void {
//     var vec_list = std.ArrayList([26]u8).init(allocator);
//     var p = combo;
//     // defer allocator.free(vec_list);
//     defer vec_list.deinit();
//     while (p != null) {
//         try vec_list.append(p.?.vec);
//         p = p.?.next;
//     }
//     const slice = try vec_list.toOwnedSlice();
//     try cartesianPrint(slice, wordmap);
    
// }

// pub fn cartesianPrint(
//     vec_list: [][26]u8,
//     wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8))
// ) !void {
//     if (vec_list.len == 0) {
//         try stdout.print("\n", .{});
//         return;
//     }
//     const vec = vec_list[0];
//     if (wordmap.get(vec)) |words| {
//         for (words.items) |word| {
//             try cartesianPrint(vec_list[1..], wordmap);
//             try stdout.print("{s} ", .{word});
//         }
//     }
// }

// fn printWordsForCurrentCombo(
//     combo: ?*Node,
//     wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
//     allocator: std.mem.Allocator,
// ) !void {
//     var word_list = std.ArrayList([]const u8).init(allocator);
//     defer word_list.deinit();
    
//     // First collect all words in the combination
//     var current = combo;
//     while (current) |node| {
//         const vec_array: [26]u8 = node.vec;
//         if (wordmap.get(vec_array)) |words| {
//             try word_list.append(words.items[0]);
//         }
//         current = node.next;
//     }
  
//     // Print all words in the combination
//     for (word_list.items) |word| {
//         try stdout.print("{s} ", .{word});
//     }
//     try stdout.writeAll("\n");
    
//     // Now generate all variations by trying different words at each position
//     var depth: usize = 0;
//     current = combo;
//     while (current) |node| : ({current = node.next; depth += 1;}) {
//         const vec_array: [26]u8 = node.vec;
//         if (wordmap.get(vec_array)) |words| {
//             const original_word = word_list.items[depth];
//             for (words.items) |word| {
//                 if (!std.mem.eql(u8, word, original_word)) {
//                     word_list.items[depth] = word;
//                     for (word_list.items) |w| {
//                         try stdout.print("{s} ", .{w});
//                     }
//                     try stdout.writeAll("\n");
//                 }
//             }
//             word_list.items[depth] = original_word;
//         }
//     }
// }


fn sumLetterCounts(vec: [26]u8) u32 {
    var sum: u32 = 0;
    for (vec) |count| {
        sum += count;
    }
    return sum;
}

fn sortVectorsBySize(vectors: [][26]u8, allocator: std.mem.Allocator) ![][26]u8 {
    const sorted = try allocator.dupe([26]u8, vectors);
    
    std.sort.block([26]u8, sorted, {}, struct {
        fn lessThan(_: void, a: [26]u8, b: [26]u8) bool {
            return sumLetterCounts(b) < sumLetterCounts(a);
        }
    }.lessThan);
    
    return sorted;
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
    // for (vectors) |key| {
    //     const vec: @Vector(26, u8) = key;
    //     if (@reduce(.Or, target_combo < vec)) {
    //         const value = hashmap.get(key);
    //         std.debug.print("{any}", .{value});
    //     }
    // }

    const sorted = try sortVectorsBySize(vectors, allocator);
    defer allocator.free(sorted);

    try printCombinations(target_combo, sorted, null, hashmap, allocator);

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
