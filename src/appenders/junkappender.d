module swfbiganal.appenders.junkappender;

import etc.c.zlib;
import swfbiganal.util.appender;

/**
 * simplified version of LimitAppender for junk data
 * - put() method doesn't modify the input buffer
 * - the overall length and crc of appended data is calculated (including ignored bytes)
 */
struct JunkAppender
{
	size_t                   limit;
	ScopedAppender!(ubyte[]) ap;

	uint                     crc;
	ulong                    total;

	invariant(ap[].length <= limit);

	private bool isValid() const
	{
		return (limit != 0);
	}

	void put(scope const(ubyte)[] buf)
	in (isValid)
	{
		size_t want = (limit - ap[].length);
		size_t have = buf.length;
		size_t copy = min(want, have);

		ap ~= buf[0..copy];

		crc = crc32(crc, buf);
		total += buf.length;
	}

	const(ubyte)[] opSlice() const
	in (isValid)
	{
		return ap[];
	}

	/**
	 * empty the contents of the appender, but keep the limit value and the appender allocation
	 */
	private // unittest only
	void clear()
	in (isValid)
	{
		ap.clear();
		crc = 0;
		total = 0;
	}

	/**
	 * reset the appender to its initial state, only keeping the appender allocation
	 */
	private // unittest only
	void reset()
	in (isValid)
	{
		clear();
		limit = 0;
	}
}

private:

auto min(A, B)(A a, B b)
if (is(A == B))
{
	if (b < a) a = b;
	return a;
}

unittest
{
	import std.string : representation; // grep: unittest

	uint crc(scope const(ubyte)[] data)
	{
		return crc32(0, data);
	}

	JunkAppender ja;

	assert(!ja.isValid);
	ja = JunkAppender(2);
	assert(ja.isValid);
	// .
	ja.put("h".representation);
	assert(ja[] == "h");
	assert(ja.total == 1);
	assert(ja.crc == crc("h".representation));
	// .
	ja.put("i".representation);
	assert(ja[] == "hi");
	assert(ja.total == 2);
	assert(ja.crc == crc("hi".representation));
	// .
	ja.put("!".representation);
	assert(ja[] == "hi");
	assert(ja.total == 3);
	assert(ja.crc == crc("hi!".representation));
	// .
	assert(ja.isValid);
	ja.reset();
	assert(!ja.isValid);

	// filled in one put()
	ja = JunkAppender(2);
	ja.put("hey".representation);
	assert(ja[] == "he");
	assert(ja.total == 3);
	assert(ja.crc == crc("hey".representation));

	// clear() keeps the appender allocation
	ja = JunkAppender(1);
	assert(ja[] is null);
	ja.put("a".representation);
	assert(ja[] !is null && ja[].length == 1);
	ja.clear();
	assert(ja[] !is null && ja[].length == 0);
}

uint crc32(uint crc, scope const(ubyte)[] data)
{
	return crc32_z(crc, data.ptr, data.length);
}
