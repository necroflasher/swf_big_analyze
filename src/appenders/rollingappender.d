module swfbiganal.appenders.rollingappender;

import core.stdc.string : memmove;
import swfbiganal.util.appender;

/**
 * An Appender-like buffer that allows removing data from its beginning once
 * it's been processed.
 */
struct RollingAppender
{
	/** NOTE: this uses malloc */
	private ScopedAppender!(ubyte[]) ap;

	/** bytes before ap[0] that have been skipped */
	private ulong startOffset;

	/** bytes at the beginning of ap[] that have been skipped */
	private size_t bufOffset;

	/**
	 * get the total length that has been appended to this appender
	 */
	public ulong totalAppended() const
	{
		return startOffset + ap[].length;
	}

	/**
	 * get the total effective offset, or how much has been skipped using advanceBy()
	 */
	public ulong effectiveOffset() const
	{
		return startOffset + bufOffset;
	}

	/**
	 * get a slice of the remaining buffered data
	 * 
	 * NOTE: returns malloced buffer - invalidated by compact()
	 */
	public const(ubyte)[] opSlice() const
	{
		return (ap[])[bufOffset..$];
	}

	public void put(scope const(ubyte[]) buf)
	{
		ap ~= buf;
	}

	/**
	 * NOTE: returns malloced buffer - invalidated by compact()
	 */
	public const(ubyte)[] advanceBy(size_t len)
	{
		size_t avail = (ap[].length - bufOffset);
		assert(len <= avail);

		const(ubyte)[] skipped = (ap[])[bufOffset..bufOffset+len];
		bufOffset += len;
		return skipped;
	}

	/**
	 * compact the appender, moving unread data to the front of the buffer
	 * 
	 * this should be used as an optimization to prevent the allocation from growing indefinitely
	 */
	public void compact()
	{
		if (bufOffset < 4*1024) // magic number (is this useful?)
			return;

		const(ubyte)[] unread = this[];

		memmove(ap[].ptr, unread.ptr, unread.length);
		ap.shrinkTo(unread.length);

		startOffset += bufOffset;
		bufOffset = 0;
	}
}

unittest
{
	RollingAppender ra;

	// empty, check properties
	ra = RollingAppender();
	assert(ra.totalAppended == 0);
	assert(ra.effectiveOffset == 0);
	assert(!ra[].length);
	assert(ra[].ptr == null);

	// append, check properties
	const(ubyte)[] someBytes = cast(ubyte[])"\x01\x02\x03\x04";
	ra.put(someBytes);
	assert(ra.totalAppended == 4);
	assert(ra.effectiveOffset == 0);
	assert(ra[] == someBytes);
	assert(ra[].ptr != someBytes.ptr);

	// advance, check properties
	assert(ra.advanceBy(1) == "\x01");
	assert(ra.totalAppended == 4);
	assert(ra.effectiveOffset == 1);
	assert(ra[] == someBytes[1..$]);

	// advance again, check properties
	assert(ra.advanceBy(2) == "\x02\x03");
	assert(ra.totalAppended == 4);
	assert(ra.effectiveOffset == 3);
	assert(ra[] == someBytes[3..$]);

	// append again, check properties
	const(ubyte)[] moreBytes = cast(ubyte[])"\x0a\x0b\x0c\x0d";
	ra.put(moreBytes);
	assert(ra.totalAppended == 8);
	assert(ra.effectiveOffset == 3);
	assert(ra[] == "\x04\x0a\x0b\x0c\x0d");
}

unittest
{
	import core.exception : AssertError; // grep: unittest

	RollingAppender ra;
	bool ok;

	// advance by 0 is harmless
	ra = RollingAppender();
	assert(ra.advanceBy(0).ptr == null);
	assert(ra.effectiveOffset == 0);

	// check that advance out of bounds asserts
	ok = false;
	ra = RollingAppender();
	try
		ra.advanceBy(1);
	catch (AssertError e)
		ok = true;
	assert(ok);
}
