const std = @import("std");
const stdout = std.io.getStdOut().writer();
// var bw = std.io.bufferedWriter(stdout);
// const w = bw.writer();

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




// Filters a list of items based on whether they fit inside the target vector
// Caller owns the returned memory
pub fn filterInside(
    items: [][26]u8,
    target: @Vector(26, u8),
    allocator: std.mem.Allocator,
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

// basic node structure for storing nodes
const VecNode = struct {
    // val: @Vector(26, u8),
    val: [26]u8,
    next: ?*VecNode,

    pub fn init(val: [26]u8, next: ?*VecNode, allocator: std.mem.Allocator) !*VecNode {
        const node = try allocator.create(VecNode);
        node.* = .{ .val = val, .next = next };
        return node;
    }
};

fn printVec(vec: [26]u8) void {
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

pub fn printAnagrams(
    target: @Vector(26, u8),
    remaining_combos: [][26]u8,
    current_combo: ?*VecNode,
    wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,
) !void {
    const zero_vector: @Vector(26, u8) = @splat(0);

    if (@reduce(.And, target == zero_vector)) {
        try printSolution(current_combo, wordmap, null, allocator);
        return;
    }

    for (remaining_combos, 0..) |vec, i| {
        const remaining = target - vec;
        const new_node = try VecNode.init(vec, current_combo, allocator);
        defer allocator.destroy(new_node);

        const filtered_combos = try filterInside(remaining_combos[i..], remaining, allocator);
        defer allocator.free(filtered_combos);

        try printAnagrams(remaining, filtered_combos, new_node, wordmap, allocator);
    }
}


const StrNode = struct {
    val: []const u8,
    next: ?*StrNode,

    pub fn init(val: []const u8, next: ?*StrNode, allocator: std.mem.Allocator) !*StrNode {
        const node = try allocator.create(StrNode);
        node.* = .{ .val = val, .next = next };
        return node;
    }
};

pub fn printList(
    list: ?*StrNode
) !void {
    var maybe_node = list;
    while (maybe_node) |node| {
        try stdout.print("{s} ", .{node.val});
        maybe_node = node.next;
    }
}

fn printSolution(
    combo: ?*VecNode,
    wordmap: std.AutoArrayHashMap([26]u8, std.ArrayList([]const u8)),
    path: ?*StrNode,
    allocator: std.mem.Allocator,
) !void {
    if (combo == null) {
        try printList(path);
        try stdout.print("\n", .{});
        return;
    }
    if (wordmap.get(combo.?.val)) |words| {
        const next_combo = combo.?.next;
        for (words.items) |word| {
            const new_path = try StrNode.init(word, path, allocator);
            defer allocator.destroy(new_path);
            try printSolution(next_combo, wordmap, new_path, allocator);
        }
    }
}

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

    try printAnagrams(target_combo, sorted, null, hashmap, allocator);
    // try bw.flush();
    // const initial_combo = std.ArrayList(@Vector(26, u8)).init(allocator);
    // const initial_combo: ?*VecNode = null;
    // try printAnagrams(target_combo, hashmap, initial_words, initial_combo, allocator);

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
