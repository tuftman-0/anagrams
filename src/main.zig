const std =	@import("std");
const stdout = std.io.getStdOut().writer();
// var bw =	std.io.bufferedWriter(stdout);
// const w = bw.writer();
// const byfreq	= "seiarntolcdupgmhbyfvkwxzjq";
// for trying different letter orders for checking
// const order:	[26]u8 = [_]u8{18, 4, 8, 0,	17,	13,	19,	14,	11,	2, 3, 20, 15, 6, 12, 7,	1, 24, 5, 21, 10, 22, 23, 25, 9, 16};
// const order:	[26]u8 = [_]u8{0, 1, 2,	3, 4, 5, 6,	7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25};
// var bw: std.io.BufferedWriter(4096, std.fs.File.Writer) = undefined;



// struct for holding a word with it's corresponding 26 vector of letter counts
const ComboPair	= struct {
	combo: [26]u8,
	word: []const u8,
};

// struct that represents the group of words associated with a particular combination of letters
const WordGroup	= struct {
	counts:	[26]u8,
	words: [][]const u8,
};

// struct used for efficiently computing whether a combination of letters can fit inside a target
const LetterCombo =	struct {
	group: WordGroup,
	set: [26]u8,
	len: u8,
};

// is a buffer that holds the current running solution (combination of WordGroups)
const ComboBuffer =	struct {
	groups:	[]WordGroup,
	len: usize,
	
	pub fn init(max_depth: usize, allocator: std.mem.Allocator)	!ComboBuffer {
		const groups = try allocator.alloc(WordGroup, max_depth);
		return .{
			.groups	= groups,
			.len = 0,
		};
	}

	pub fn deinit(self:	*ComboBuffer, allocator: std.mem.Allocator)	void {
		allocator.free(self.groups);
	}

	pub fn appendGroup(self: *ComboBuffer, group: WordGroup) void {
		self.groups[self.len] =	group;
		self.len +=	1;
	}

	pub fn removeLast(self:	*ComboBuffer) void {
		self.len -=	1;
	}
};

// holds buffers used for filtering the arrays of possible LetterCombo at each level
const FilterBuffers	= struct {
	// Array of slices,	each slice is a buffer for a level
	buffers: [][]*LetterCombo,
	allocator: std.mem.Allocator,

	pub fn init(max_depth: usize, max_width: usize,	allocator: std.mem.Allocator) !FilterBuffers {
		const buffers =	try allocator.alloc([]*LetterCombo,	max_depth);
		errdefer allocator.free(buffers);

		// Allocate each level's buffer
		for	(buffers) |*buffer|	{
			buffer.* = try allocator.alloc(*LetterCombo, max_width);
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
		items: []*LetterCombo,
		target:	[26]u8,
	) []*LetterCombo {
		const buffer = self.buffers[depth];
		var size: usize	= 0;

		for	(items)	|item| {
			if (fitsInside(target, item.*))	{
				buffer[size] = item;
				size +=	1;
			}
		}

		return buffer[0..size];
	}
};

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


// reads words from file
// https://stackoverflow.com/a/77053872/8062159
pub fn readWordsFromFile(
	filename: []const u8,
	allocator: std.mem.Allocator
) ![][]const u8	{
	const file = try std.fs.cwd().openFile(filename, .{});
	defer file.close();
	const file_size	= try file.getEndPos();
	const buffer = try allocator.alloc(u8, file_size);
	// defer allocator.free(buffer); //	breaks everything because it frees too early
	_ =	try file.readAll(buffer);
	var lines =	std.mem.splitSequence(u8, buffer, "\n");
	var words =	std.ArrayList([]const u8).init(allocator);
	while (lines.next()) |line|	{
		const trimmed =	std.mem.trimRight(u8, line,	" \r");
		if (trimmed.len	> 0) {
			try words.append(trimmed);
		}
	}
	return words.toOwnedSlice();
}

pub fn fitsInside(
	target:	[26]u8,
	combo: LetterCombo
) bool {
	for	(0..combo.len) |i| {
		const pos: u8 =	combo.set[i];
		if (combo.group.counts[pos] > target[pos]) {
			return false;
		}
	}
	return true;
}


// // alternate that uses vectors (kinda makes sets irrelevant) seems about the same performance as the regular fits inside
// pub fn fitsInside(
// 	target:	@Vector(26,u8),
// 	combo: LetterCombo
// ) bool {
// 	return @reduce(.And, combo.group.counts <= target);
// }


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

fn buildCombos(
	pairs: []ComboPair,
	allocator: std.mem.Allocator,
) ![]LetterCombo {
	// First sort by vectors
	std.sort.block(ComboPair, pairs, {}, struct	{
		fn lessThan(_: void, a:	ComboPair, b: ComboPair) bool {
			return vectorCompare(a.combo, b.combo);
		}
	}.lessThan);

	// Now group them
	var combos = std.ArrayList(LetterCombo).init(allocator);
	var words =	std.ArrayList([]const u8).init(allocator);
	errdefer words.deinit();
	errdefer combos.deinit();

	var current_vec	= pairs[0].combo;
	try words.append(pairs[0].word);

	for	(pairs[1..]) |pair|	{
		if (std.mem.eql(u8,	&current_vec, &pair.combo))	{
			try words.append(pair.word);
		} else {
			// Create combo for previous group
			var combo =	LetterCombo{
				.group = .{
					.counts	= current_vec,
					.words = try words.toOwnedSlice(),
				},
				.set = undefined,
				.len = 0,
			};
			
			// Build set for efficient checking
			for	(current_vec, 0..) |count, i| {
				if (count >	0) {
					combo.set[combo.len] = @intCast(i);
					combo.len += 1;
				}
			}
			
			try combos.append(combo);

			// Start new group
			current_vec	= pair.combo;
			try words.append(pair.word);
		}
	}

	// Don't forget last group
	var combo =	LetterCombo{
		.group = .{
			.counts	= current_vec,
			.words = try words.toOwnedSlice(),
		},
		.set = undefined,
		.len = 0,
	};
	for	(current_vec, 0..) |count, i| {
		if (count >	0) {
			combo.set[combo.len] = @intCast(i);
			combo.len += 1;
		}
	}
	try combos.append(combo);

	return try combos.toOwnedSlice();
}

// words ->	combo word pairs ->	filtered combo word pairs -> words grouped by combo

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


// filters a set of words based on whether they fit inside a target string
// returns a slice of word,	vector pairs
// where the vectors represent a particular combination of leters
pub fn getFilteredWordComboPairs(
	words: [][]const u8,
	target:	[]const u8,
	allocator: std.mem.Allocator
) ![]ComboPair {
	const target_counts	= getLetterCounts(target);
	var pairs: []ComboPair = try allocator.alloc(ComboPair,	words.len);
	// maybe just use arraylist for simplicity
	var size: usize	= 0;
	for	(words)	|word| {
		const word_counts =	getLetterCounts(word);
		// if word doesn't fit inside target then skip it
		if (!fitsInsideVec(target_counts, word_counts))	{
			continue;
		}
		pairs[size]	= .{ .combo	= word_counts, .word = word	};
		size +=	1;
	}
	_ =	allocator.resize(pairs,	size);
	return pairs[0..size];
}

// Filters a list of items based on whether they fit inside the target vector
// Caller owns the returned memory
pub fn filterInside(
	items: []*LetterCombo,
	target:	[26]u8,
	allocator: std.mem.Allocator,
) ![]*LetterCombo {
	var list = std.ArrayList(*LetterCombo).init(allocator);
	errdefer list.deinit();
	for	(items)	|item| {
		if (fitsInside(target, item.*))	{
			try list.append(item);
		}
	}
	return try list.toOwnedSlice();
}

// prints all the extended anagrams of a particular combination of characters 
pub fn printAnagrams(
	target:	*@Vector(26, u8),
	remaining_combos: []*LetterCombo,
	combo_buffer: *ComboBuffer,
	filter_buffers:	*FilterBuffers,
	solution_buffer: *SolutionBuffer,
	depth: usize,
) !void	{
	const zero_vector: @Vector(26, u8) = @splat(0);
	// once a solution (combination of WordGroups) is reached, print all combinations of words associated with this solution
	if (fitsInsideVec(zero_vector, target.*)) {
		try printSolution(combo_buffer,	solution_buffer);
		return;
	}

	for	(remaining_combos, 0..)	|combo,	i| {
		target.* = target.*	- combo.group.counts;
		
		combo_buffer.appendGroup(combo.group);

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
		target.* = target.*	+ combo.group.counts;
	}
}

// prints all the combinations of words associated with a particular combination of WordGroups
pub fn printSolution(
	combo_buffer: *const ComboBuffer,
	solution_buffer: *SolutionBuffer,
) !void	{
	if (combo_buffer.len ==	0) {
		if (solution_buffer.len	> 0) {
			try stdout.writeAll(solution_buffer.bytes[0	.. solution_buffer.len - 1]);
			try stdout.writeByte('\n');
		}
		return;
	}

	const group	= combo_buffer.groups[0];
	for	(group.words) |word| {
		solution_buffer.appendWord(word);
		var next_buffer	= ComboBuffer{
			.groups	= combo_buffer.groups[1..],
			.len = combo_buffer.len	- 1,
		};
		try printSolution(&next_buffer,	solution_buffer);
		solution_buffer.removeLast(word.len);
	}
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
	var target_combo: @Vector(26, u8)  = getLetterCounts(target);

	const words	= try readWordsFromFile("/home/josh/.local/bin/words.txt", allocator);
	defer allocator.free(words);
	// std.debug.print("{d}	words in wordlist\n", .{words.len});

	// std.debug.print("{any}: {s}\n", .{ target_combo,	target });
	const pairs	= try getFilteredWordComboPairs(words, target, allocator);
	defer allocator.free(pairs);

	const combos = try buildCombos(pairs, allocator);
	defer {
		for	(combos) |combo| allocator.free(combo.group.words);
		allocator.free(combos);
	}

	var pointers = try allocator.alloc(*LetterCombo, combos.len);
	defer allocator.free(pointers);
	for	(combos, 0..) |*combo, i| {
		pointers[i]	= combo;
	}

	// sort pointers
	std.sort.block(*LetterCombo, pointers, {}, struct {
	    fn lessThan(_: void, a: *LetterCombo, b: *LetterCombo) bool {
	        return sumLetterCounts(b.group.counts) < sumLetterCounts(a.group.counts);
	    }
	}.lessThan);

	var combo_buffer = try ComboBuffer.init(target.len,	allocator);
	defer combo_buffer.deinit(allocator);

	var filter_buffers = try FilterBuffers.init(target.len,	combos.len,	allocator);
	defer filter_buffers.deinit();

	var solution_buffer	= try SolutionBuffer.init(target.len * 2, allocator);
	defer solution_buffer.deinit(allocator);

	try printAnagrams(
		&target_combo,
		pointers,
		&combo_buffer,
		&filter_buffers,
		&solution_buffer,
		0,
	);
	// try bw.flush();
}

test "read words" {
	const allocator	= std.heap.page_allocator;
	const words	= try readWordsFromFile("/home/josh/.local/bin/words.txt", allocator);
	defer allocator.free(words);
	for	(words)	|word| {
		std.debug.print("{s} ",	.{word});
	}
	std.debug.print("\n{d}\n", .{words.len});
}
