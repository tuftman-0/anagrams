const std =	@import("std");
const clap = @import("clap");
const builtin = @import("builtin");
const stdout = std.io.getStdOut().writer();
// *TODO* add windows compatibility (either switch to using universal constructs or make separate windows and linux implementations)
// *TODO* length based grouping logic for speed
// *TODO* add proper error handling

// OLD: words -> combo word pairs -> filtered combo word pairs -> words grouped by combo
// NEW: words -> filter + add into map from combos to groups -> from map create array of WordGroups
// WordGroups contain {combination of letters, slice of words represented by that combination , # of repetitions of this group in a solution}
// in our printAnagrams function we produce every combination of WordGroups that exactly add up to the target
// once a solution is produce we pass it to the printSolution function
// which goes through the lists of words that each WordGroup represents
// printing all of the combinations of words that exist for that solution

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
		// FNV-1a
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
const GroupsMap = std.HashMap(ComboKey, std.ArrayList([]const u8), ComboKeyHashFns, 85);

//returns a vector of counts for each letter in an input word
pub fn getLetterCounts(
	word: []const u8,
) [26]u8 {
	// construct a 26 byte long array to store the number of each letter
	var counts:	[26]u8 = std.mem.zeroes([26]u8);
	for	(word) |char| {
		switch (char) {
			'a'...'z' => { counts[char - 'a'] += 1;	}, // transform lowercase
			'A'...'Z' => { counts[char - 'A'] += 1;	}, // transform uppercase
			else	  => {}, // do nothing
		}
	}
	return counts;
}

// checks if vector a can fit inside vector b
// used for checking if the set of letters a WordGroup is a subset of the letters in the target
// I already tried a more complicated system where I also stored the set of nonzero indices in each combination to be checked
// and only checked the values at those indices
// it was slower than these vector calculations by a very small margin
pub fn fitsInsideVec(
	b: @Vector(26,u8),
	a: @Vector(26,u8),
) bool {
	return @reduce(.And, a <= b);
}

const FileStuff = struct {
	map: GroupsMap,  // Change from pointer to owned value
	mmap: []align(4096) const u8,

	pub fn deinit(self: *FileStuff) void {
		std.posix.munmap(@constCast(self.mmap));
	}
};

// function for reading a word list file and building a hashmap
// builds a map from combinations of letters to the group of words that each combo represents
pub fn buildMapFromFile(
	filename: []const u8,
	target_counts: [26]u8,
	allocator: std.mem.Allocator,
) !FileStuff {
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

	// // ***USE FOR WINDOWS*** (will have to change FileStuff to work with this)
	// const buffer = try allocator.alloc(u8, file_size);
	// defer allocator.free(buffer);
	// _ = try file.readAll(buffer);

	var lines = std.mem.splitSequence(u8, buffer, "\n");
	var map = GroupsMap.init(allocator);

	while (lines.next()) |word| {
		if (word.len == 0) continue;

		const word_counts = getLetterCounts(word);
		if (!fitsInsideVec(target_counts, word_counts)) continue;

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

	return FileStuff{
		.map  = map,
		.mmap = buffer
	};
}

// struct that represents the group of words associated with a particular combination of letters
const WordGroup	= struct {
	counts:	[26]u8,      // counts of each of the letters
	words: [][]const u8, // slice of all the words that this combo represents
	len: usize           // total number of letters
};

// function that takes the map from combos to groups and makes a slice of WordGroups
//
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
		const combo_key = entry.key_ptr;

		groups[i] = WordGroup{
			.counts = combo_key.counts,
			.words  = entry.value_ptr.items,
			.len    = sumLetterCounts(combo_key.counts),
		};
		i += 1;
	}

	return groups[0..length];
}

// holds buffers used for filtering the arrays of possible WordGroup at each level
const FilterBuffers = struct {
	// Array of slices, each slice is a buffer for a level
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

	// Filter items into the buffer at the given depth
	
	pub fn filterAtDepth(
		self: *FilterBuffers,
		depth: usize,
		items: []*WordGroup,
		target:	@Vector(26,u8),
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

// used for keeping track of repetitions
const RepeatedGroup = struct {
	group: *WordGroup,
	reps: usize,
};

// is a buffer that holds the current running solution (combination of WordGroups)
const ComboBuffer = struct {
	groups: []RepeatedGroup,
	len: usize,

	pub fn init(max_depth: usize, allocator: std.mem.Allocator) !ComboBuffer {
		const groups = try allocator.alloc(RepeatedGroup, max_depth);
		return ComboBuffer{
			.groups = groups,
			.len = 0,
		};
	}

	pub fn appendGroup(self: *ComboBuffer, group: *WordGroup) void {
		// if group is the same as the last group just increment repetitions
		if (self.len > 0 and self.groups[self.len - 1].group == group) {
			self.groups[self.len - 1].reps += 1;
			return;
		}
		// otherwise add a group with 1 repetition
		self.groups[self.len] = RepeatedGroup{
			.group = group,
			.reps = 1
		};
		self.len += 1;
	}

	pub fn removeLast(self: *ComboBuffer) void {
		if (self.groups[self.len-1].reps > 1) {
			self.groups[self.len-1].reps -= 1;
		} else {
			self.len -= 1;
		}
	}
};

pub fn printAnagrams(
	target:	*@Vector(26, u8),
	length: usize,
	remaining_groups: []*WordGroup,
	combo_buffer: *ComboBuffer,
	filter_buffers:	*FilterBuffers,
	solution_buffer: *SolutionBuffer,
	depth: usize,
) !void {
	// once a solution (combination of WordGroups) is reached, print all combinations of words associated with this solution
	if (length == 0) {
		const solution = combo_buffer.groups[0..combo_buffer.len];
		try printSolution(solution, solution_buffer);
		return;
	}
	for	(remaining_groups, 0..)	|group, i| {
		target.* = target.*	- group.counts;
		combo_buffer.appendGroup(group);

		const filtered_groups =	filter_buffers.filterAtDepth(
			depth,
			remaining_groups[i..],
			target.*,
		);

		try printAnagrams(
			target,
			length - group.len,
			filtered_groups,
			combo_buffer,
			filter_buffers,
			solution_buffer,
			depth +	1,
		);
		combo_buffer.removeLast();
		target.* = target.*	+ group.counts;
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

// prints all of the combinations of words represented by a solution (combination of WordGroups)
pub fn printSolution(
	groups: []RepeatedGroup,
	solution_buffer: *SolutionBuffer,
) anyerror!void {
	if (groups.len == 0) {
		if (solution_buffer.len > 0) {
			try stdout.writeAll(solution_buffer.bytes[0..solution_buffer.len - 1]);
			try stdout.writeByte('\n');
		}
		return;
	}
	const rep_group = groups[0];
	try combosInPlace(rep_group.group.words, rep_group.reps, solution_buffer, groups[1..]);
}


// A helper function for choosing combinations of `words` with `reps` repetitions
fn combosInPlace(
	words: [][]const u8,
	reps: usize,
	solution_buffer: *SolutionBuffer,
	rest: []RepeatedGroup,
) anyerror!void {
	if (reps == 0) {
		return printSolution(rest, solution_buffer);
	}
	for (words, 0..) |word, i| {
		solution_buffer.appendWord(word);
		try combosInPlace(words[i..], reps - 1, solution_buffer, rest);
		solution_buffer.removeLast(word.len);
	}
}

fn sumLetterCounts(counts: [26]u8) usize {
	var sum: usize = 0;
	for (counts) |count| {
		sum += count;
	}
	return sum;
}

fn printCombo(combo: [26]u8) !void {
	for (combo, 0..) |count, i| {
		const idx: u8 = @truncate(i);
		const char = 'a' + idx;
		for (0..count) |_| {
			try stdout.print("{c}", .{char});
		}
	}
}


pub fn main() !void	{
	var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	defer arena.deinit();
	const allocator	= arena.allocator();
	const err_writer = std.io.getStdErr().writer();

	const params = comptime clap.parseParamsComptime(
		\\-h, --help       Display this help and exit.
		\\-f, --file <str> Use custom word list file.
		\\<str>...
		\\
	);

	var diag = clap.Diagnostic{};
	const res  = clap.parse(clap.Help, &params, clap.parsers.default, .{
		.diagnostic = &diag,
		.allocator  = allocator,
	}) catch |err| {
		diag.report(err_writer, err) catch {};
		return err;
	};

	if (res.args.help != 0) {
		try clap.help(err_writer, clap.Help, &params, .{});
		return;
	}

	const filename = res.args.file orelse "/home/josh/.local/bin/words.txt";
	var input: []const u8 = undefined;
	// max input size is 26*255=6630 letters due to [26]u8 representation but we give extra room for other non letter chars
	var input_buf: [8192]u8 = undefined;

	if (res.positionals.len > 0) {
		// input = res.positionals[0][0];
		// Copy each positional argument into the allocated buffer
		var offset: usize = 0;
		for (res.positionals[0]) |arg| {
			// std.mem.copy(u8, all_input[offset..], arg);  // Copy each argument

			@memcpy(input_buf[offset..(offset+arg.len)], arg);  // Copy each argument
			offset += arg.len;  // Update the offset for the next argument
		}

		// Now `all_input` contains the concatenated string from all positionals
		input = input_buf[0..offset];
	} else {
		// Read from stdin
		const stdin = std.io.getStdIn();
		const bytes_read = try stdin.read(&input_buf);
		input = std.mem.trimRight(u8, input_buf[0..bytes_read], "\r\n");
	}

	var target_counts: @Vector(26, u8) = getLetterCounts(input);
	const target_length = sumLetterCounts(target_counts);

	var file_stuff = try buildMapFromFile(filename, target_counts, allocator);
	defer file_stuff.deinit(); // close file
	var map = file_stuff.map;
	if (map.count() == 0) { return; } // if there are no remaining words end early

	const groups = try buildWordGroupsFromMap(&map, allocator);

	


	// sort WordGroups by number of characters for prettiness and potential speed
	std.sort.block(WordGroup, groups, {}, struct {
		fn lessThan(_: void, a: WordGroup, b: WordGroup) bool {
			return b.len < a.len;
		}
	}.lessThan);

	// const maxlen = sumLetterCounts(groups[0]);
	// const minlen = sumLetterCounts(groups[groups.len - 1]);
	// lengths = allocator.alloc();
	// for (groups, 0..) |group, i| {  }
	var pointers = try allocator.alloc(*WordGroup, groups.len);
	for	(groups, 0..) |*group, i| {
		pointers[i]	= group;

	}



	const target_len = sumLetterCounts(target_counts);
	// // doesn't really work *TODO* find solution
	// find overestimate for max recursion depth by adding the lengths of the smallest wordgroups until we reach the target_len
	var curr_len: usize = 0;
	var max_depth: usize = 1; // minimum depth is 1
	var i: usize = pointers.len - 1;
	while (curr_len < target_len and i > 0) : (i -= 1) {
		const counts = pointers[i].*.counts;
		const len = sumLetterCounts(counts);
		curr_len += len;
		max_depth += 1;
		// std.debug.print(": {d}, target_len: {d}, max: {d}\n", .{len, target_len, max_depth});
	}
	// std.debug.print("input length: {d}\n", .{input.len});


	// *TODO* this could probably allocate less if we figure out a way to put better bounds on it
	var combo_buffer = try ComboBuffer.init(max_depth, allocator);

	var filter_buffers = try FilterBuffers.init(target_len, groups.len, allocator);

	var solution_buffer = try SolutionBuffer.init(input.len * 2, allocator);

	if (true) try printAnagrams(
		&target_counts,
		target_length,
		pointers,
		&combo_buffer,
		&filter_buffers,
		&solution_buffer,
		0,
	);
}


// serialization format for potential storing of WordGroups, so initial processing can be skipped
// File format:
// [26 bytes for counts][4 bytes for num_words][word1\n][word2\n]...[wordN\n]
// Repeated for each WordGroup
