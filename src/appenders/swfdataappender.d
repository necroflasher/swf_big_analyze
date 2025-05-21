module swfbiganal.appenders.swfdataappender;

import etc.c.zlib : crc32_z;
import swfbiganal.appenders.junkappender;
import swfbiganal.appenders.rollingappender;
import swfbiganal.swfbitreader;
import swfbiganal.swftypes.swfheader;

public struct SwfDataAppender
{
	private enum State
	{
		// waiting for initialize() to be called with the swf header
		readHeader,

		// reading movie data
		readData,

		// reading ended normally
		// when set, further swf data will be put in unusedSwfData
		endedNormally,

		// reading ended because a tag overflowed the file
		// when set, further swf data will be put in overflowSwfData
		endedWithOverflow,
	}

	private State state;
	private RollingAppender swfData;

	/**
	 * size limit for swfData, set from the swf header in initialize()
	 */
	private size_t swfDataLimit;

	// stats
	public size_t swfDataValidTotal; // how much valid swfData has been read
	public uint   swfDataValidCrc;   // overall crc of valid swfData

	/**
	 * tag stream data that was ignored because a tag overflows the header size
	 */
	public JunkAppender overflowSwfData = {limit: 512};

	/**
	 * tag stream data that was ignored because an End tag was reached
	 */
	public JunkAppender unusedSwfData   = {limit: 512};

	/**
	 * data after the tag stream that wasn't included in the header size
	 */
	public JunkAppender junkData        = {limit: 512};

	invariant
	{
		assert(swfData.totalAppended <= swfDataLimit);

		// only .readData uses swfData
		assert(state == State.readData || !swfData[].length);

		// only .endedNormally uses unusedSwfData
		assert(state == State.endedNormally || !unusedSwfData[].length);

		// only .endedWithOverflow uses overflowSwfData
		assert(state == State.endedWithOverflow || !overflowSwfData[].length);
	}

	/**
	 * true if the appender has been initialized
	 */
	private bool isInitialized() const
	{
		return state != State.readHeader;
	}

	/**
	 * true if reading ended because of an overflow
	 * (setSwfReadFinishedWithOverflow() was called)
	 */
	public bool isOverflowed() const
	{
		return state == State.endedWithOverflow;
	}

	/**
	 * true if reading ended for any reason
	 */
	public bool isEnded() const
	{
		return (
			state == State.endedNormally ||
			state == State.endedWithOverflow
		);
	}

	/**
	 * get a SwfBitReader for parsing the currently buffered data
	 * 
	 * note that using the reader doesn't automatically advance the position of
	 * this buffer - use advanceBy() to do that
	 * 
	 * NOTE: the buffer is malloced - invalidated by compact()
	 */
	public SwfBitReader getReader() const
	in (isInitialized)
	{
		// only makes sense to call this in .reading
		// swfData is empty in other states
		assert(state == State.readData);

		return SwfBitReader(swfData[]);
	}

	/**
	 * get the current read offset as bytes into the uncompressed swf file
	 * 
	 * for compressed files, this won't match the file on disk but an imaginary
	 *  decompressed version of it
	 * 
	 * the offset matches ffdec's hexdump view for both uncompressed and
	 *  compressed files
	 */
	public ulong swfReadOffset() const
	{
		return SwfHeader.sizeof + swfData.effectiveOffset;
	}

	/**
	 * initialize the appender (gets the size limit from the header)
	 */
	public void initialize(ref const(SwfHeader) swfHeader)
	in (!isInitialized)
	out (; isInitialized)
	{
		state = State.readData;

		if (swfHeader.fileSize < SwfHeader.sizeof)
			swfDataLimit = 0;
		else
			swfDataLimit = (swfHeader.fileSize - SwfHeader.sizeof);
	}

	/**
	 * Feed some data into the appender. This sorts it into the appropriate
	 * buffer according to the SWF header's size field.
	 */
	public void put(scope const(ubyte)[] buf)
	in (isInitialized)
	{
		ulong swfReadRemaining = (swfDataLimit - swfData.totalAppended);

		/*
		 * were we still waiting for swf data?
		 */
		if (swfReadRemaining)
		{
			size_t swfCopy = cast(size_t)min(cast(ulong)buf.length, swfReadRemaining);
			final switch (state)
			{
				case State.readHeader:
					assert(0);
				case State.readData:
					swfData.put(buf[0..swfCopy]);
					break;
				case State.endedNormally:
					unusedSwfData.put(buf[0..swfCopy]);
					break;
				case State.endedWithOverflow:
					overflowSwfData.put(buf[0..swfCopy]);
					break;
			}
			buf = buf[swfCopy..$];
		}

		if (buf.length)
			junkData.put(buf);
	}

	/**
	 * advance the read position after successfully reading `i` bytes
	 */
	public void advanceBy(size_t len)
	in (isInitialized)
	{
		const(ubyte)[] skipped = swfData.advanceBy(len);

		// update stats
		swfDataValidTotal += len;
		swfDataValidCrc = crc32(swfDataValidCrc, skipped);
	}

	/**
	 * Called to end reading after the tag stream has been fully parsed.
	 */
	public void setSwfReadFinished()
	in (isInitialized)
	{
		assert(state == State.readData);
		state = State.endedNormally;

		unusedSwfData.put(swfData[]);
		swfData.destroy(); // no longer needed
	}

	/**
	 * Called to end reading due to a tag overflowing the file.
	 */
	public void setSwfReadFinishedWithOverflow()
	in (isInitialized)
	{
		assert(state == State.readData);
		state = State.endedWithOverflow;

		// detect likely misuse
		// swfreader needs stuff in the buffer to detect overflow in the first place
		assert(swfData[].length);

		overflowSwfData.put(swfData[]);
		swfData.destroy(); // no longer needed
	}

	/**
	 * compact the swfData buffer
	 * 
	 * this moves the remaining un-read data to the beginning and shrinks the buffer
	 * 
	 * this should be used to prevent the Appender from infinitely growing its allocation
	 * 
	 * NOTE: readers from getReader() are invalidated by this as they contain malloced data
	 */
	public void compact()
	in (isInitialized)
	{
		swfData.compact();
	}
}

private:

auto min(A, B)(A a, B b)
if (is(A == B))
{
	if (b < a) a = b;
	return a;
}

uint crc32(uint crc, scope const(ubyte)[] data)
{
	return crc32_z(crc, data.ptr, data.length);
}
