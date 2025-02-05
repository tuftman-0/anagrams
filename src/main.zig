const std =	@import("std");
const builtin = @import("builtin");
pub const use_mmap = (builtin.os.tag == .linux or builtin.os.tag == .macos);
const stdout = std.io.getStdOut().writer();

// struct for holding a word with it's corresponding 26 vector of letter counts
const ComboPair	= struct {
	combo: [26]u8,
	word: []const u8,
};



// 1) A 26-byte key + hash + eq
const ComboKey = struct {
	counts: [26]u8,

	fn hash(self: *const @This()) u64 {
		// simple FNV-1a
		var result: u64 = 0xcbf29ce484222325;
		inline for (self.counts) |b| {
			result = (result ^ b) * 0x100000001b3;
		}
		return result;
	}

	fn eql(a: *const @This(), b: *const @This()) bool {
		return std.mem.eql(u8, &a.counts, &b.counts);
	}
};

const ComboKeyHashFns = struct {
	pub fn hash(self: ComboKeyHashFns, key: ComboKey) u64 {
		_ = self;
		// FNV-1a example
		var result: u64 = 0xcbf29ce484222325;
		inline for (key.counts) |b| {
			result = (result ^ b) *% 0x100000001b3;
		}
		return result;
	}

	pub fn eql(self: ComboKeyHashFns, a: ComboKey, b: ComboKey) bool {
		_ = self;
		return std.mem.eql(u8, &a.counts, &b.counts);
	}
};


// We'll store: ComboKey -> std.ArrayList([]const u8)
// so each key (letter combo) has a dynamic array of words.
const GroupsMap = std.HashMap(ComboKey, std.ArrayList([]const u8), ComboKeyHashFns, 75);

pub fn buildWordGroupsFromMap(
	map: *GroupsMap,
	allocator: std.mem.Allocator,
) ![]WordGroup {
	// map.items() => iterator over .key and .value
	var items = map.iterator();
	const length = map.count();

	// We'll build an array of WordGroup, one per distinct letter combo
	var groups = try allocator.alloc(WordGroup, length);
	var i: usize = 0;

	while (items.next()) |entry| {
		const combo_key = entry.key_ptr;           // ComboKey
		// const array_list = entry.value_ptr;        // std.ArrayList([]const u8)

		groups[i] = WordGroup{
			.counts = combo_key.counts,
			// Convert the ArrayList of words into a slice
			// .words  = try array_list.toOwnedSlice(),
			.words = entry.value_ptr.items,
			.reps   = 1, // can start with 1
		};
		i += 1;
	}

	return groups[0..length];
}

//returns a vector of counts for each letter in an input word
pub fn getLetterCounts(
	word: []const u8
) [26]u8 {
	// construct a 26 byte long array to store the number of each letter
	var counts:	[26]u8 = std.mem.zeroes([26]u8);
	for	(word) |char| {
		switch (char) {
			'a'...'z' => { counts[char - 'a'] += 1;	}, // transform lowercase
			'A'...'Z' => { counts[char - 'A'] += 1;	}, // transform uppercase
			else	  => {}, //	do nothing
		}
	}
	return counts;
}

// checks if vector a can fit inside vector b
// used for checking if a WordGroup can fit inside a target
pub fn fitsInsideVec(
	b: @Vector(26,u8),
	a: @Vector(26,u8),
) bool {
	return @reduce(.And, a <= b);
}

fn vectorCompare(a:	[26]u8,	b: [26]u8) bool	{
	for	(a,	b) |a_val, b_val| {
		if (a_val != b_val)	return a_val < b_val;
	}
	return false;
}

// words ->	combo word pairs ->	filtered combo word pairs -> words grouped by combo

// struct that represents the group of words associated with a particular combination of letters
const WordGroup	= struct {
	counts:	[26]u8, // counts of each of the letters
	words: [][]const u8, // slice of all the words that this combo represents
	reps: usize, // number of times that this combination is repeated in a solution
};

// holds buffers used for filtering the arrays of possible WordGroup at each level
const FilterBuffers	= struct {
	// Array of slices,	each slice is a buffer for a level
	buffers: [][]*WordGroup,
	allocator: std.mem.Allocator,

	pub fn init(max_depth: usize, max_width: usize,	allocator: std.mem.Allocator) !FilterBuffers {
		const buffers =	try allocator.alloc([]*WordGroup,	max_depth);
		errdefer allocator.free(buffers);

		// Allocate each level's buffer
		for	(buffers) |*buffer|	{
			buffer.* = try allocator.alloc(*WordGroup, max_width);
		}

		return FilterBuffers{
			.buffers = buffers,
			.allocator = allocator,
		};
	}

	pub fn deinit(self:	*FilterBuffers)	void {
		// Free each level's buffer
		for	(self.buffers) |buffer|	{
			self.allocator.free(buffer);
		}
		// Free the array of buffers
		self.allocator.free(self.buffers);
	}

	// Filter items into the buffer at the given depth
	pub fn filterAtDepth(
		self: *FilterBuffers,
		depth: usize,
		items: []*WordGroup,
		target:	[26]u8,
	) []*WordGroup {
		const buffer = self.buffers[depth];
		var size: usize	= 0;

		for	(items)	|item| {
			if (fitsInsideVec(target, item.counts))	{
				buffer[size] = item;
				size +=	1;
			}
		}

		return buffer[0..size];
	}
};

// is a buffer that holds the current running solution (combination of WordGroups)
const ComboBuffer =	struct {
	groups:	[]*WordGroup,
	len: usize,

	pub fn init(max_depth: usize, allocator: std.mem.Allocator)	!ComboBuffer {
		const groups = try allocator.alloc(*WordGroup, max_depth);
		return .{
			.groups	= groups,
			.len = 0,
		};
	}

	pub fn deinit(self:	*ComboBuffer, allocator: std.mem.Allocator)	void {
		allocator.free(self.groups);
	}

	pub fn appendGroup(self: *ComboBuffer, group: *WordGroup) void {
		// if the previous word is the same then just increment count
		if (self.len > 0) {
			const last_group_ptr = self.groups[self.len - 1];
			// if (std.mem.eql(u8, &last_group_ptr.counts, &group.counts)) {
			if (last_group_ptr == group) {
				last_group_ptr.reps += 1;
				return;
			}
		}
		self.groups[self.len] =	group;
		self.len +=	1;
	}

	pub fn removeLast(self:	*ComboBuffer) void {
		if (self.groups[self.len-1].reps > 1) {
			self.groups[self.len-1].reps -= 1;
		} else {
			self.len -=	1;
		}
	}
};

// prints all the extended anagrams of a particular combination of characters 
pub fn printAnagrams(
	target:	*@Vector(26, u8),
	remaining_combos: []*WordGroup,
	combo_buffer: *ComboBuffer,
	filter_buffers:	*FilterBuffers,
	solution_buffer: *SolutionBuffer,
	depth: usize,
) !void	{
	const zero_vector: @Vector(26, u8) = @splat(0);
	// once a solution (combination of WordGroups) is reached, print all combinations of words associated with this solution
	if (fitsInsideVec(zero_vector, target.*)) {
		// try printSolution(combo_buffer,	solution_buffer);
		// try printSolutionNoPermutations(combo_buffer, solution_buffer, 0);
		const solution = combo_buffer.groups[0..combo_buffer.len];
		try printSolutionDeduped(solution, solution_buffer);
		return;
	}

	for	(remaining_combos, 0..)	|combo, i| {
		target.* = target.*	- combo.counts;
		combo_buffer.appendGroup(combo);

		const filtered_combos =	filter_buffers.filterAtDepth(
			depth,
			remaining_combos[i..],
			target.*,
		);

		try printAnagrams(
			target,
			filtered_combos,
			combo_buffer,
			filter_buffers,
			solution_buffer,
			depth +	1,
		);
		combo_buffer.removeLast();
		target.* = target.*	+ combo.counts;
	}
}

// holds the solution (string) a combination of words
const SolutionBuffer = struct {
	bytes: []u8,
	len: usize,

	pub fn init(max_bytes: usize, allocator: std.mem.Allocator)	!SolutionBuffer	{
		const bytes	= try allocator.alloc(u8, max_bytes);
		return .{
			.bytes = bytes,
			.len = 0,
		};
	}

	pub fn deinit(self:	*SolutionBuffer, allocator:	std.mem.Allocator) void	{
		allocator.free(self.bytes);
	}

	// Add a word plus a space
	pub fn appendWord(self:	*SolutionBuffer, word: []const u8) void	{
		@memcpy(self.bytes[self.len..self.len +	word.len], word);
		self.bytes[self.len	+ word.len]	= ' ';
		self.len +=	word.len + 1;
	}

	// Remove last word plus its trailing space
	pub fn removeLast(self:	*SolutionBuffer, word_len: usize) void {
		self.len -=	word_len + 1;
	}
};

pub fn printSolutionNoPermutations(
	combo_buffer: *const ComboBuffer,
	solution_buffer: *SolutionBuffer,
	index: usize,
) anyerror!void {
	// If we've processed all groups, print the current line.
	if (index == combo_buffer.len) {
		if (solution_buffer.len > 0) {
			// Print everything except trailing space
			try stdout.writeAll(solution_buffer.bytes[0 .. solution_buffer.len - 1]);
			try stdout.writeByte('\n');
		}
		return;
	}

	// Otherwise, pick `combo_buffer.groups[index].reps` words from .words
	const group = combo_buffer.groups[index];
	const needed = group.reps;

	// We'll do an in-place recursion to choose exactly `needed` items from group.words.
	try combosInPlace2(
		group.words,
		needed,
		0,  // start index in group.words
		combo_buffer,
		solution_buffer,
		index
	);
}

// A helper function for "choose `needed` items from `words` (ignoring order)"
fn combosInPlace2(
    words: [][]const u8,
    needed: usize,
    start_index: usize,
    combo_buffer: *const ComboBuffer,
    solution_buffer: *SolutionBuffer,
    group_index: usize,
) anyerror!void {
    // If we've picked all items for this group, move on to next group
    if (needed == 0) {
        return printSolutionNoPermutations(combo_buffer, solution_buffer, group_index + 1);
    }

    // If no more words to choose from
    if (start_index >= words.len) {
        return; // no solution at this branch
    }

    // 1) Pick words[start_index]
    const w = words[start_index];
    solution_buffer.appendWord(w);
    // We still allow picking the same index again, because "combinations with repetition".
    try combosInPlace2(words, needed - 1, start_index, combo_buffer, solution_buffer, group_index);
    solution_buffer.removeLast(w.len);

    // 2) Skip words[start_index] => increment start_index
    try combosInPlace2(words, needed, start_index + 1, combo_buffer, solution_buffer, group_index);
}


pub fn printSolutionDeduped(
	groups: []*const WordGroup,
	solution_buffer: *SolutionBuffer,
) anyerror!void {
	if (groups.len == 0) {
		// Print the line
		if (solution_buffer.len > 0) {
			try stdout.writeAll(solution_buffer.bytes[0 .. solution_buffer.len - 1]);
			try stdout.writeByte('\n');
		}
		return;
	}

	const group = groups[0];
	try combosInPlace(group.words, group.reps, solution_buffer, groups[1..]);
}

fn combosInPlace(
	words: [][]const u8,
	needed: usize,
	solution_buffer: *SolutionBuffer,
	rest: []*const WordGroup,
) anyerror!void {
	if (needed == 0) {
		return printSolutionDeduped(rest, solution_buffer);
	}
	if (words.len == 0) {
		return;
	}
	// pick words[0]
	const w = words[0];
	solution_buffer.appendWord(w);
	try combosInPlace(words, needed - 1, solution_buffer, rest);
	solution_buffer.removeLast(w.len);
	// skip words[0]
	try combosInPlace(words[1..], needed, solution_buffer, rest);
}


fn sumLetterCounts(vec:	[26]u8)	u32	{
	var sum: u32 = 0;
	for	(vec) |count| {
		sum	+= count;
	}
	return sum;
}

pub fn main() !void	{
	var gpa	= std.heap.GeneralPurposeAllocator(.{}){};
	const allocator	= gpa.allocator();
	const filename = "/home/josh/.local/bin/words.txt";
	// const filename = "/home/josh/.local/bin/wordswodupes.txt";

	// bw =	std.io.bufferedWriter(std.io.getStdOut().writer());
	// defer bw.flush()	catch unreachable;

	// Get command line args
	var args = try std.process.argsWithAllocator(allocator);
	defer args.deinit();

	// Skip program name
	_ =	args.next();

	// Get input either from args or stdin
	var input: []const u8 =	undefined;
	var input_buf: [1024]u8	= undefined;

	if (args.next()) |arg| {
		// Use command line argument
		input =	arg;
	} else {
		// Read from stdin
		const stdin	= std.io.getStdIn();
		const bytes_read = try stdin.read(&input_buf);
		input =	std.mem.trimRight(u8, input_buf[0..bytes_read],	"\r\n");
	}

	const target = input;
	var target_counts: @Vector(26, u8)  = getLetterCounts(target);


	// file processing starts=========================================
	const file = try std.fs.cwd().openFile(filename, .{});
	defer file.close();
	// get file size
	const file_size	= try file.getEndPos();

	// ***USE FOR LINUX/MAC***
	const buffer = try std.posix.mmap(
		null,
		file_size,
		std.posix.PROT.READ,
		.{.TYPE = .SHARED},
		file.handle,
		0,
	);
	defer std.posix.munmap(buffer);

	// ***USE FOR WINDOWS***
	// const buffer = try allocator.alloc(u8, file_size);
	// defer allocator.free(buffer);
	// _ = try file.readAll(buffer);

	var lines = std.mem.splitSequence(u8, buffer, "\n");
	// var pairs_list = std.ArrayList(ComboPair).init(allocator);
	// while (lines.next()) |word|	{
	// 	if (word.len > 0) {
	// 		// std.debug.print("{s},", .{word});
 //    		const word_counts =	getLetterCounts(word);
 //    		if (!fitsInsideVec(target_counts, word_counts)) continue;
 //            try pairs_list.append(.{
 //                .combo = word_counts,
 //                .word  = word
 //            });
	// 	}
	// }
	// const pairs = try pairs_list.toOwnedSlice();
	// defer allocator.free(pairs);
	// if (pairs.len == 0) return;

	// file processing ends===========================================

	// const groups = try buildGroups(pairs, allocator);
	// defer {
	// 	for	(groups) |combo| allocator.free(combo.words);
	// 	allocator.free(groups);
	// }


	// 1) Initialize the map
	var map = GroupsMap.init(allocator);
	defer map.deinit(); // We'll build WordGroups from this map, then free it

	while (lines.next()) |word| {
		if (word.len == 0) continue;

		const word_counts = getLetterCounts(word);
		if (!fitsInsideVec(target_counts, word_counts)) continue;

		// Build key
		const key = ComboKey{ .counts = word_counts };

		// Insert or retrieve existing
		const res = try map.getOrPut(key);
		if (res.found_existing) {
			// key already exists in the map
			try res.value_ptr.*.append(word);
		} else {
			// newly inserted => must initialize res.value_ptr.*
			res.value_ptr.* = std.ArrayList([]const u8).init(allocator);
			try res.value_ptr.*.append(word);
		}

	}

	const groups = try buildWordGroupsFromMap(&map, allocator);
		defer {
			// free each group.words
			// for (groups) |g| {
			// 	allocator.free(g.words);
			// }
			allocator.free(groups);
		}

	var pointers = try allocator.alloc(*WordGroup, groups.len);
	defer allocator.free(pointers);
	for	(groups, 0..) |*combo, i| {
		pointers[i]	= combo;
	}

	// sort pointers
	std.sort.block(*WordGroup, pointers, {}, struct {
		fn lessThan(_: void, a: *WordGroup, b: *WordGroup) bool {
			return sumLetterCounts(b.counts) < sumLetterCounts(a.counts);
		}
	}.lessThan);

	var combo_buffer = try ComboBuffer.init(target.len,	allocator);
	defer combo_buffer.deinit(allocator);

	var filter_buffers = try FilterBuffers.init(target.len,	groups.len,	allocator);
	defer filter_buffers.deinit();

	var solution_buffer	= try SolutionBuffer.init(target.len * 2, allocator);
	defer solution_buffer.deinit(allocator);

	try printAnagrams(
		&target_counts,
		pointers,
		&combo_buffer,
		&filter_buffers,
		&solution_buffer,
		0,
	);
}

