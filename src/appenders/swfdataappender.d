module swfbiganal.appenders.swfdataappender;

import etc.c.zlib : crc32_z;
import swfbiganal.appenders.junkappender;
import swfbiganal.appenders.rollingappender;
import swfbiganal.swfbitreader;
import swfbiganal.swftypes.swfheader;

/**
 * do-it-all appender for swf data
 * 
 * - the amount put in the swfData buffer is limited by the size in the swf
 *    header (matches how flash player reads flashes)
 * - data beyond that is put in the junkData buffer, whose size is capped by its .limit
 * - crc and sizes are calculated for you
 * - hands out SwfBitReader instances and keeps the read position for them
 * - etc etc
 */

/**
 * An Appender-like buffer for reading a SWF file after decompression.
 * 
 * After the SWF header has been read and decompression possibly started, this
 * should be called with the movie header and the following tag stream data.
 */
public struct SwfDataAppender
{
	private enum ReadState
	{
		/// initial state
		reading,

		/// reading ended normally
		/// when set, further swf data will be put in unusedSwfData
		endedNormally,

		/// reading ended because a tag overflowed the file
		/// when set, further swf data will be put in overflowSwfData
		endedWithOverflow,
	}

	private ReadState readState;
	private RollingAppender swfData;

	/**
	 * size limit for swfData, set from the swf header in initialize()
	 */
	private size_t swfDataLimit;

	// stats
	public size_t swfDataValidTotal; /// how much valid swfData has been read
	public uint   swfDataValidCrc;   /// overall crc of valid swfData

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

		// only .reading uses swfData
		assert(readState == ReadState.reading || !swfData[].length);

		// only .endedNormally uses unusedSwfData
		assert(readState == ReadState.endedNormally || !unusedSwfData[].length);

		// only .endedWithOverflow uses overflowSwfData
		assert(readState == ReadState.endedWithOverflow || !overflowSwfData[].length);
	}

	/**
	 * true if the appender has been initialized
	 */
	private bool isInitialized() const
	{
		return (swfDataLimit != 0);
	}

	/**
	 * true if reading ended because of an overflow
	 * (setSwfReadFinishedWithOverflow() was called)
	 */
	public bool isOverflowed() const
	{
		return readState == ReadState.endedWithOverflow;
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
		assert(readState == ReadState.reading);

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
		// checks duplicated from swftypes.d
		// it doesn't matter but try to sensibly handle broken files here
		// use the header size if it looks valid, otherwise max out the limit
		enum minSwfData = 1+2+2;
		if (swfHeader.fileSize >= SwfHeader.sizeof+minSwfData && swfHeader.fileSize < 0x8000_0000)
			swfDataLimit = (swfHeader.fileSize - SwfHeader.sizeof);
		else
			swfDataLimit = (int.max - SwfHeader.sizeof); // highest normally accepted value
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
			final switch (readState)
			{
				case ReadState.reading:
					swfData.put(buf[0..swfCopy]);
					break;
				case ReadState.endedNormally:
					unusedSwfData.put(buf[0..swfCopy]);
					break;
				case ReadState.endedWithOverflow:
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
		assert(readState == ReadState.reading);
		readState = ReadState.endedNormally;

		unusedSwfData.put(swfData[]);
		swfData.destroy(); // no longer needed
	}

	/**
	 * Called to end reading due to a tag overflowing the file.
	 */
	public void setSwfReadFinishedWithOverflow()
	in (isInitialized)
	{
		assert(readState == ReadState.reading);
		readState = ReadState.endedWithOverflow;

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
