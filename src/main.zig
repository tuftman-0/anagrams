const std =	@import("std");
const clap = @import("clap");
const builtin = @import("builtin");
const stdout = std.io.getStdOut().writer();

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
			else	  => {}, //	do nothing
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
        // self.map.deinit(); // not needed because of arena allocator
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

	// ***USE FOR WINDOWS*** (will have to change FileStuff to work with this)
	// const buffer = try allocator.alloc(u8, file_size);
	// defer allocator.free(buffer);
	// _ = try file.readAll(buffer);

	var lines = std.mem.splitSequence(u8, buffer, "\n");
	var map = GroupsMap.init(allocator);

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

	return FileStuff{
		.map  = map,
		.mmap = buffer
	};
}

// struct that represents the group of words associated with a particular combination of letters
const WordGroup	= struct {
	counts:	[26]u8,      // counts of each of the letters
	words: [][]const u8, // slice of all the words that this combo represents
	reps: usize,         // number of times that this combination is repeated in a solution
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
			.reps   = 1,
		};
		i += 1;
	}

	return groups[0..length];
}

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

	// // not needed since we're using an arena allocator
	// pub fn deinit(self:	*FilterBuffers)	void {
	// 	// Free each level's buffer
	// 	for	(self.buffers) |buffer|	{
	// 		self.allocator.free(buffer);
	// 	}
	// 	// Free the array of buffers
	// 	self.allocator.free(self.buffers);
	// }

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

	// // not needed since we're using an arena allocator
	// pub fn deinit(self:	*ComboBuffer, allocator: std.mem.Allocator)	void {
	// 	allocator.free(self.groups);
	// }

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
	// if (std.mem) {
		const solution = combo_buffer.groups[0..combo_buffer.len];
		try printSolution(solution, solution_buffer);
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

	// // not needed since we're using an arena allocator
	// pub fn deinit(self:	*SolutionBuffer, allocator:	std.mem.Allocator) void	{
	// 	allocator.free(self.bytes);
	// }

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


// A helper function for choosing combinations of `words` with `reps` repetitions
fn combosInPlace(
	words: [][]const u8,
	reps: usize,
	solution_buffer: *SolutionBuffer,
	rest: []*const WordGroup,
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

fn sumLetterCounts(vec:	[26]u8)	u32	{
	var sum: u32 = 0;
	for	(vec) |count| {
		sum	+= count;
	}
	return sum;
}

pub fn main() !void	{
	// var gpa	= std.heap.GeneralPurposeAllocator(.{}){};
	// const allocator	= gpa.allocator();
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



	const filename = res.args.file orelse "/home/josh/.local/bin/words.txt";

	var input: []const u8 = undefined;
	var input_buf: [1024]u8 = undefined;

	if (res.args.help != 0) {
		try clap.help(err_writer, clap.Help, &params, .{});
		return;
	}
	if (res.positionals.len > 0) {
		// Use first positional argument
		input = res.positionals[0];
	} else {
		// Read from stdin
		const stdin = std.io.getStdIn();
		const bytes_read = try stdin.read(&input_buf);
		input = std.mem.trimRight(u8, input_buf[0..bytes_read], "\r\n");
	}

	// Get command line args
	// var args = try std.process.argsWithAllocator(allocator);
	// defer args.deinit();

	// // Skip program name
	// _ =	args.next();

	// // Get input either from args or stdin
	// var input: []const u8 =	undefined;
	// var input_buf: [1024]u8	= undefined;

	// if (args.next()) |arg| {
	// 	// Use command line argument
	// 	input =	arg;
	// } else {
	// 	// Read from stdin
	// 	const stdin	= std.io.getStdIn();
	// 	const bytes_read = try stdin.read(&input_buf);
	// 	input =	std.mem.trimRight(u8, input_buf[0..bytes_read],	"\r\n");
	// }

	var target_counts: @Vector(26, u8) = getLetterCounts(input);

	var file_stuff = try buildMapFromFile(filename, target_counts, allocator);
	defer file_stuff.deinit(); // close file
	var map = file_stuff.map;

	const groups = try buildWordGroupsFromMap(&map, allocator);
	// defer  allocator.free(groups);
	
	var pointers = try allocator.alloc(*WordGroup, groups.len);
	// defer allocator.free(pointers);
	for	(groups, 0..) |*combo, i| {
		pointers[i]	= combo;
	}

	// sort WordGroup pointers by number of characters for prettiness and potential speed
	std.sort.block(*WordGroup, pointers, {}, struct {
		fn lessThan(_: void, a: *WordGroup, b: *WordGroup) bool {
			return sumLetterCounts(b.counts) < sumLetterCounts(a.counts);
		}
	}.lessThan);

	// *TODO* this could probably allocate less if we figure out a way to put better bounds on it
	var combo_buffer = try ComboBuffer.init(input.len,	allocator);
	// defer combo_buffer.deinit(allocator);

	var filter_buffers = try FilterBuffers.init(input.len,	groups.len,	allocator);
	// defer filter_buffers.deinit();

	var solution_buffer	= try SolutionBuffer.init(input.len * 2, allocator);
	// defer solution_buffer.deinit(allocator);

	try printAnagrams(
		&target_counts,
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
