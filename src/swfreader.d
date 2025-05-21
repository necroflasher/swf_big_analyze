module swfbiganal.swfreader;

import core.stdc.stdarg;
import core.stdc.stdio;
import core.stdc.string;
import etc.c.zlib;
import swfbiganal.appenders.junkappender;
import swfbiganal.appenders.limitappender;
import swfbiganal.appenders.swfdataappender;
import swfbiganal.cdef.lzma;
import swfbiganal.swf.errors;
import swfbiganal.swfbitreader;
import swfbiganal.swftypes.swfheader;
import swfbiganal.swftypes.swfmovieheader;
import swfbiganal.swftypes.swftag;
import swfbiganal.swftypes.swflzmaextradata;
import swfbiganal.swftypes.swfrect;
import swfbiganal.util.compiler;
import swfbiganal.util.datacrc;
import swfbiganal.util.decompressor;
import swfbiganal.util.enumset;
import swfbiganal.util.explainbytes;

// 32bit
private size_t bitsToBytes(ulong bits)
{
	pragma(inline, true);
	return cast(size_t)(bits >> 3);
}

struct SwfReader
{
	public enum State
	{
		readSwfHeader,
		readCompressionHeader,
		readMovieHeader,
		readTagData,
		finished,
	}

	public State              state;

	public SwfHeader          swfHeader;
	public SwfMovieHeader     movieHeader;
	private size_t            movieHeaderSize;
	public LimitAppender2!13  compressionHeader = {limit: 13};

	private LimitAppender2!13 fileData;   /// temporary for holding header data
	private bool              endOfInput; /// no more data will be coming in

	private AnyDecomp         decompressor;
	private bool              decompressorEndOfOutput; /// decompression finished, no more output
	private JunkAppender      decompressorUnusedData;  /// extra data past zlib/lzma body

	private SwfDataAppender   swfData;

	public EnumSet!SwfSoftError softErrors;
	public EnumSet!SwfHardError hardErrors;

	public bool hasErrors()
	{
		return !softErrors.isEmpty || !hardErrors.isEmpty;
	}

	public void initialize()
	{
		setJunkSizeLimit(32);
	}

	public ~this()
	{
		decompressor.base.deinitialize();
	}

	/**
	 * set a limit on how much junk data to keep buffered
	 */
	public void setJunkSizeLimit(size_t size)
	{
		// nothing has been appended yet
		assert(!decompressorUnusedData.total);
		assert(!swfData.unusedSwfData.total);
		assert(!swfData.junkData.total);

		decompressorUnusedData.limit = size;
		swfData.overflowSwfData.limit = size;
		swfData.unusedSwfData.limit = size;
		swfData.junkData.limit = size;
	}

	/**
	 * feed more data into the reader
	 */
	public void put(scope const(ubyte)[] data)
	in (!endOfInput)
	{
		final switch (state)
		{
			case State.readSwfHeader:
			{
				putSwfHeaderData(data);
				break;
			}

			case State.readCompressionHeader:
			{
				putCompressionHeaderData(data);
				break;
			}

			// decompressor initialized
			case State.readMovieHeader:
			case State.readTagData:
			case State.finished:
			{
				putDecompressSwfData(data);
				break;
			}
		}
	}

	version (unittest)
	public void put(string data)
	{
		put(cast(const(ubyte)[])data);
	}

	/**
	 * tell the reader that there will be no more data coming in
	 * 
	 * notes:
	 * - this doesn't change .state
	 * - nextTag() should be called after this if you were reading tags
	 */
	public void putEndOfInput()
	in (!endOfInput)
	{
		endOfInput = true;

		final switch (state)
		{
			case State.readSwfHeader:
			{
				softErrors.add(SwfSoftError.movieTooShort);
				emitWarning("swf header incomplete");
				break;
			}
			case State.readCompressionHeader:
			{
				softErrors.add(SwfSoftError.movieTooShort);
				emitWarning("compression header incomplete");
				break;
			}
			case State.readMovieHeader:
			{
				softErrors.add(SwfSoftError.movieTooShort);
				emitWarning("movie header incomplete");
				break;
			}
			case State.readTagData:
			{
				// tag reading in progress
				// the next readTag will see endOfInput and update the state
				// movieTooShort: will be set through readTag
				break;
			}
			case State.finished:
			{
				// reached end of tag stream, no more parsing
				// movieTooShort: already set through readTag
				break;
			}
		}

		// were we still decompressing stuff?
		if (
			state > State.readCompressionHeader &&
			swfHeader.isCompressed &&
			!decompressorEndOfOutput)
		{
			emitWarning("unexpected end of compressed body");
		}
	}

	/**
	 * called by readTag when we're done reading tags [after setting swfData to
	 *  finished, before updating state]
	 */
	private void onSwfDataFinished()
	in (
		state == State.readTagData &&
		swfData.isEnded)
	{
		// total movie data (including overflowed tags and tags past end)
		size_t totalMovieData = swfData.swfDataValidTotal;
		totalMovieData += swfData.unusedSwfData.total;
		totalMovieData += swfData.overflowSwfData.total;

		assert(movieHeaderSize >= 5); // smallest valid, should have it here
		size_t displayRectSize = movieHeaderSize-4;

		assert(totalMovieData >= movieHeaderSize);
		size_t tagStreamSize = totalMovieData - movieHeaderSize;

		// based on testing, flash player's limits for a minimal swf seem to be:
		// tag data >= 6 bytes
		// tags+rect >= 9 bytes
		// tag data here includes overflowing/unused data, limited by header size

		if (tagStreamSize < 6 || totalMovieData < 9)
		{
			//~ printf("movieTooShort: tagStreamSize=%zu totalMovieData=%zu\n",
				//~ tagStreamSize,
				//~ totalMovieData);

			//~ printf("swfDataValidTotal=%llu\n", swfData.swfDataValidTotal);
			//~ printf("unusedSwfData=%llu\n", swfData.unusedSwfData.total);
			//~ printf("overflowSwfData=%llu\n", swfData.overflowSwfData.total);

			softErrors.add(SwfSoftError.movieTooShort);
		}
	}

	/**
	 * for unittest purposes (to get the errors set), parses all the remaining
	 *  tags in the file
	 * 
	 * this should be done before checking hasErrors if no tags are read
	 */
	private void skipRemainingTags()
	{
		SwfTag tag;
		while (readTag(tag))
			continue;
	}

	/**
	 * read the next tag if available
	 * 
	 * note: `tagOut.data` points to an internal buffer whose contents may be
	 *  overwritten by the next call to readTag() or put()
	 */
	public bool readTag(out SwfTag tagOut)
	{
		if (expect(state != State.readTagData, false))
			return false;

		/*
		 * did we overflow the swf data earlier?
		 * if so, just wait for the file to end and set State.finished when it happens
		 */
		if (expect(swfData.isOverflowed, false))
		{
			if (endOfInput)
				state = State.finished;

			return false;
		}

		auto br = swfData.getReader();

		// ended cleanly without an end tag (no excess data)
		if (!br.totalBits && endOfInput)
		{
			swfData.setSwfReadFinished();
			onSwfDataFinished();
			state = State.finished;
			return false;
		}

		uint   x      = br.read!ushort;
		uint   code   = x >> 6;
		size_t length = x & 0b111111;

		bool longFormat = (length == 0x3f);
		if (longFormat)
		{
			length = br.read!uint;
		}

		bool   tagHeaderOverflow = br.overflow;
		size_t tagHeaderSize = bitsToBytes(br.curBit);

		const(ubyte)[] tagData = br.readBytesNoCopy(length);

		// not enough data to parse the tag?
		if (br.overflow)
		{
			/*
			 * already read the file, no more data coming in?
			 */
			if (expect(endOfInput, false))
			{
				const(char)* specific;
				if (br.data.length < 2)
				{
					specific = "tag code and length";
				}
				else if (longFormat && br.data.length < 6)
				{
					specific = "long tag length";
				}

				if (specific)
				{
					explainBytes(br.data, (scope exp)
					{
						emitWarning("overflow reading %s (bytes=<%.*s>)",
							specific,
							cast(int)exp.length, exp.ptr,
							);
					});
				}
				else
				{
					size_t tagDataAvail = (br.data.length - 2);
					if (longFormat)
						tagDataAvail -= 4;

					explainBytes(br.data, 12, (scope exp)
					{
						emitWarning("overflow reading tag data (code=%u length=%zu avail=%zu bytes=<%.*s>)",
							code,
							length,
							tagDataAvail,
							cast(int)exp.length, exp.ptr,
							);
					});
				}

				swfData.setSwfReadFinishedWithOverflow();
				onSwfDataFinished();
				state = State.finished;
				return false;
			}
			/*
			 * so we're not finished reading. would the tag data actually fit in the file?
			 * 
			 * 1. if the end exceeds the uncompressed filesize, the tag would be ignored - so no need to buffer it
			 * 2. if the end exceeds int.max, flash player closes
			 * 
			 * this pretty much just detects the other overflow case early, before "br.overflow && endOfInput" is true
			 */
			if (expect(!tagHeaderOverflow, true)) // <-- check it only if we could read this thing
			{
				ulong tagDataEnd = swfData.swfReadOffset + tagHeaderSize + length;
				if (expect(tagDataEnd > swfHeader.fileSize, false))
				{
					if (tagDataEnd > 0x7fff_ffff)
					{
						hardErrors.add(SwfHardError.tagEndOverflow);
						emitWarning("tag end overflows int.max: %llu > %u",
							tagDataEnd,
							int.max,
							);
					}
					else
						emitWarning("tag data would overflow file: %llu > %u (extra: %llu)",
							tagDataEnd,
							swfHeader.fileSize,
							tagDataEnd - swfHeader.fileSize,
							);

					swfData.setSwfReadFinishedWithOverflow();
					onSwfDataFinished();
					// call recursively once to check the end condition
					return readTag(tagOut);
				}
			}
			/*
			 * so we're just finished reading tags for now.
			 * 
			 * use this opportunity to compact the buffer
			 * 
			 * NOTE: invalidates malloc, but there should be no references to it
			 */
			swfData.compact();

			return false;
		}

		{
			// old gdc lacks named arguments
			SwfTag tmp = {
				code:       code,
				data:       tagData,
				longFormat: longFormat,
				fileOffset: swfData.swfReadOffset,
			};
			tagOut = tmp;
		}

		swfData.advanceBy(bitsToBytes(br.curBit));

		// end tag?
		if (expect(code == 0, false))
		{
			swfData.setSwfReadFinished();
			onSwfDataFinished();
			state = State.finished;
		}

		return true;
	}

	/// overall size of valid swf data (movie header and parsed tags)
	public ulong validSwfDataSize() const
	{
		return swfData.swfDataValidTotal;
	}

	/// overall crc of valid swf data (movie header and parsed tags)
	public uint validSwfDataCrc() const
	{
		return swfData.swfDataValidCrc;
	}

	/**
	 * Get the "unused SWF data" of the file.
	 * 
	 * - For both compressed and uncompressed files, this is the data included
	 *   in the file size specified in the SWF header that wasn't consumed when
	 *   reading tags.
	 */
	public DataCrc getUnusedSwfData() const
	{
		// must read tags to completion first
		if (state != State.finished)
		{
			return DataCrc.init;
		}

		return DataCrc.from(swfData.unusedSwfData);
	}

	/**
	 * Get the "overflow SWF data" of the file.
	 * 
	 * - For both compressed and uncompressed files, this is the data included
	 *   in the file size specified in the SWF header that was ignored because
	 *   a tag overflows the size.
	 */
	public DataCrc getOverflowSwfData() const
	{
		return DataCrc.from(swfData.overflowSwfData);
	}

	/**
	 * Get the "compressed junk data" of the file.
	 * 
	 * - For compressed files, this is data inside the compressed body that
	 *   wasn't included in the uncompressed file size specified in the SWF
	 *   header.
	 */
	public DataCrc getCompressedJunkData() const
	{
		if (swfHeader.isCompressed)
		{
			return DataCrc.from(swfData.junkData);
		}
		else
		{
			return DataCrc.init;
		}
	}

	/**
	 * Get the "EOF junk data" of the file.
	 * 
	 * - For compressed files, this is data after the compressed zlib/lzma
	 *   stream in the file.
	 * 
	 * - For uncompressed files, this is data past the file size specified in
	 *   the SWF header.
	 */
	public DataCrc getEofJunkData() const
	{
		if (swfHeader.isCompressed)
		{
			return DataCrc.from(decompressorUnusedData);
		}
		else
		{
			return DataCrc.from(swfData.junkData);
		}
	}

	@cold
	private void emitWarning(string msg)
	{
		pragma(inline, false);
		printf("# %.*s\n", cast(int)msg.length, msg.ptr);
	}

	@cold
	extern(C)
	pragma(printf)
	private void emitWarning(scope const(char)* fmt, scope ...)
	{
		pragma(inline, false);
		va_list ap;
		va_start(ap, fmt);
		printf("# ");
		vprintf(fmt, ap);
		printf("\n");
		va_end(ap);
	}

	/**
	 * called by put() when reading the swf reader
	 */
	private void putSwfHeaderData(scope const(ubyte)[] data)
	in (state == State.readSwfHeader)
	{
		if (!fileData.limit)
		{
			fileData.limit = SwfHeader.sizeof;
		}
		fileData.appendFromRef(data);

		if (!fileData.isFull)
			return;

		swfHeader = fileData[].as!SwfHeader;
		fileData.reset();

		const(char)* invalidReason = swfHeader.validate(&softErrors);
		if (invalidReason)
		{
			explainBytes(swfHeader.asBytes, 8, (scope exp)
			{
				emitWarning("bad swf header (%s): %.*s",
					invalidReason,
					cast(int)exp.length, exp.ptr);
			});
		}

		swfData.initialize(swfHeader);

		if (swfHeader.isCompressed)
		{
			state = State.readCompressionHeader;
		}
		else
		{
			decompressor.null_.initialize();
			state = State.readMovieHeader;
		}

		if (data.length)
			put(data);
	}

	/**
	 * called by put() when reading the zlib/lzma compression header
	 */
	private void putCompressionHeaderData(scope const(ubyte)[] data)
	in (state == State.readCompressionHeader)
	{
		assert(swfHeader.isCompressed);

		if (!fileData.limit)
		{
			if (swfHeader.isZlibCompressed)
				fileData.limit = 2;
			if (swfHeader.isLzmaCompressed)
				fileData.limit = SwfLzmaExtraData.sizeof;
		}
		fileData.appendFromRef(data);

		if (!fileData.isFull)
			return;

		// if the zlib header says that a dictionary should be used, then read 4 more bytes for its checksum
		// flash doesn't support this, will say "Movie not loaded"
		// https://stackoverflow.com/a/30794147
		// https://stackoverflow.com/a/54915442
		if (swfHeader.isZlibCompressed && ((fileData[])[1] & 0b1_00000))
		{
			fileData.limit = 6;
			fileData.appendFromRef(data);

			if (!fileData.isFull)
				return;
		}

		compressionHeader = fileData[].idup;
		fileData.reset();

		/*
		 * ok, we have the relevant compression header and can start
		 * decompressing now
		 * 
		 * create the decompressor and pass it the header we read
		 */

		state = State.readMovieHeader;

		if (swfHeader.isZlibCompressed)
		{
			checkZlibHeader();

			if (expect(!decompressor.zlib.initialize(), false))
				decompressor.null_.initialize();

			put(compressionHeader[]);
		}
		else if (swfHeader.isLzmaCompressed)
		{
			checkLzmaHeader();

			if (expect(!decompressor.lzma.initialize(), false))
				decompressor.null_.initialize();

			// the lzma header contains a field for the expected size of decompressed data.
			// we can set this, or leave it at -1 which would make it auto-detected based on the stream
			// let's try setting it and see what happens

			// it is unknown which way gives closer behavior to what flash player does
			// it doesn't help that it doesn't even use the same library (it uses lzma sdk)

			enum uncompHeadersSize = SwfHeader.sizeof;

			ulong uncompDataSize = swfHeader.fileSize;
			if (uncompDataSize >= uncompHeadersSize)
				uncompDataSize -= uncompHeadersSize;
			else
				uncompDataSize = 0; // nonsense but just don't underflow it

			put(compressionHeader[]
				.as!SwfLzmaExtraData
				.toLzmaHeader(uncompDataSize)
				.asBytes);
		}

		if (data.length)
			put(data);
	}

	private void checkZlibHeader()
	{
		// 2 or 6 bytes
		assert(compressionHeader.length >= 2);

		// https://www.rfc-editor.org/rfc/rfc1950
		uint method  = compressionHeader[0] & 0b1111;
		uint info    = compressionHeader[0] >> 4;
		uint check   = compressionHeader[1] & 0b11111;
		uint usedict = (compressionHeader[1] >> 5) & 1;
		uint level   = compressionHeader[1] >> 6;

		uint combined = compressionHeader[0]*256+compressionHeader[1];
		if (expect(combined % 31 != 0, false))
		{
			emitWarning("zlib header error: checksum mismatch: 0x%04x %% 31 != 0", combined);
			return;
		}

		if (expect(method != 8, false))
		{
			emitWarning("zlib header error: unknown compression method %u", method);
			return;
		}

		if (expect(info > 7, false))
		{
			// note: actual window size is this value plus eight
			emitWarning("zlib header error: bad window size value: %u > 7", info);
		}

		if (expect(usedict != 0, false))
		{
			emitWarning("zlib header error: dictionary required to decompress");
		}
	}

	private void checkLzmaHeader()
	{
		auto header = compressionHeader[].as!SwfLzmaExtraData;

		// https://git.tukaani.org/?p=xz.git;a=blob;f=doc/lzma-file-format.txt;h=4865defd5cf22716d68dbc4621897e6186afffe5;hb=HEAD

		// lc: "the number of literal context bits"
		// lp: "the number of literal position bits"
		// pb: "the number of position bits"
		uint prop = header.properties;
		uint pb = prop / (9 * 5);
		prop -= pb * 9 * 5;
		uint lp = prop / 9;
		uint lc = prop - lp * 9;

		if (header.properties > (4 * 5 + 4) * 9 + 8)
		{
			emitWarning("lzma header error: bad properties field");
			return;
		}

		// "XZ Utils has an additional requirement: lc + lp <= 4."
		// we can't decompress this, while flash player uses the lzma sdk which isn't affected
		// just reject the file as unsupported
		if (lc + lp > 4)
		{
			emitWarning("lzma header error: unsupported file");
			return;
		}
	}

	/**
	 * called by put() when we're in the compressed part
	 */
	private void putDecompressSwfData(scope const(ubyte)[] data)
	in (
		state == State.readMovieHeader ||
		state == State.readTagData ||
		state == State.finished)
	{
		assert(data.length);

		if (!decompressorEndOfOutput)
		{
			int err = decompressor.base.put(data, (scope buf)
			{
				swfData.put(buf);
				return 0;
			});
			if (expect(err != 0, false))
			{
				const(char)* type = decompressor.base.type();
				const(char)* errmsg = decompressor.base.strerror(err);
				ulong bytesIn = decompressor.base.bytesIn;
				ulong bytesOut = decompressor.base.bytesOut;
				emitWarning("%s decompression error: %s (code=%d in=%llu out=%llu)",
					type,
					errmsg,
					err,
					bytesIn,
					bytesOut,
					);
			}
		}

		// decompression finished?
		if (data !is null)
		{
			//fprintf(stderr, "-end of decompressed output\n");
			assert(swfHeader.isCompressed); // uncompressed shouldn't get here
			decompressorEndOfOutput = true;
			decompressorUnusedData.put(data);
		}

		if (state == State.readMovieHeader)
		{
			auto br = swfData.getReader();
			movieHeader = SwfMovieHeader(br);
			if (!br.overflow)
			{
				movieHeaderSize = bitsToBytes(br.curBit);
				swfData.advanceBy(movieHeaderSize);
				// ok, ready to read tags now
				state = State.readTagData;
			}
		}
	}
}

private:

version (unittest)
ubyte[] compress(string data)
{
	static import std.zlib; // grep: unittest
	return std.zlib.compress(cast(ubyte[])data);
}

version (unittest)
ubyte[] compress2(string data)
{
	import swfbiganal.cdef.lzma;

	lzma_options_lzma lol;
	if (lzma_lzma_preset(&lol, 0))
		assert(0);

	lzma_stream ls;
	if (lzma_alone_encoder(&ls, &lol) != lzma_ret.OK)
		assert(0);

	ls.next_in = cast(const(ubyte)*)data.ptr;
	ls.avail_in = data.length;
	// let's hope it gets smaller!
	ubyte[] buf = new ubyte[data.length*4];
	ls.next_out = buf.ptr;
	ls.avail_out = buf.length;

	lzma_ret rv = lzma_code(&ls, lzma_action.FINISH);
	if (rv != lzma_ret.STREAM_END)
		assert(0);
	assert(!ls.avail_in);

	lzma_end(&ls);

	size_t outlen = (buf.length - ls.avail_out);

	return buf[0..outlen];
}

// tiny swf, ends normally without an end tag
unittest
{
	auto sr = SwfReader();
	sr.put("FWS\x01");
	sr.put(uint(21).asBytes);
	sr.put("\x00"); // rect
	sr.put("\x00\x00"); // frameRate
	sr.put("\x00\x00"); // frameCount
	sr.putEndOfInput();

	SwfTag tag;
	if (sr.readTag(tag)) assert(0);

	assert(sr.hasErrors);
	assert(sr.softErrors.has(SwfSoftError.movieTooShort));
}

// normal uncompressed swf
unittest
{
	auto sr = SwfReader();
	sr.initialize();
	sr.put("FWS\x01");
	sr.put(uint(21).asBytes);
	sr.put("\x00"); // rect
	sr.put("\xab\xcd"); // frameRate
	assert(sr.validSwfDataSize == 0);
	sr.put("\x12\x34"); // frameCount
	assert(sr.validSwfDataSize == 5);
	sr.put("\x00\x00"); // End
	sr.putEndOfInput();
	assert(!sr.hasErrors);

	assert(sr.movieHeader.frameRate[0] == 0xab);
	assert(sr.movieHeader.frameRate[1] == 0xcd);
	assert(sr.movieHeader.frameCount == 0x3412);

	SwfTag tag;
	assert(sr.validSwfDataSize == 5);
	if (!sr.readTag(tag)) assert(0);
	assert(sr.validSwfDataSize == 7);
	assert(tag.code == 0);
	assert(!tag.data.length);
	if (sr.readTag(tag)) assert(0);

	assert(sr.getUnusedSwfData[] == "");
	assert(sr.getEofJunkData[] == "");

	assert(sr.hasErrors);
	assert(sr.softErrors.has(SwfSoftError.movieTooShort));
}

// normal compressed swf
unittest
{
	auto sr = SwfReader();
	sr.initialize();
	sr.put("CWS\x01");
	sr.put(uint(21).asBytes);
	sr.put(compress(
		"\x00"~     // rect
		"\xab\xcd"~ // frameRate
		"\x12\x34"~ // frameCount
		"\x00\x00"  // End
	));
	sr.putEndOfInput();
	assert(!sr.hasErrors);

	assert(sr.movieHeader.frameRate[0] == 0xab);
	assert(sr.movieHeader.frameRate[1] == 0xcd);
	assert(sr.movieHeader.frameCount == 0x3412);

	SwfTag tag;
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 0);
	assert(!tag.data.length);
	if (sr.readTag(tag)) assert(0);

	assert(sr.getUnusedSwfData[] == "");
	assert(sr.getCompressedJunkData[] == "");
	assert(sr.getEofJunkData[] == "");

	assert(sr.hasErrors);
	assert(sr.softErrors.has(SwfSoftError.movieTooShort));
}

// lzma-compressed swf
unittest
{
	string movie =
		"\x00"~     // rect
		"\xab\xcd"~ // frameRate
		"\x12\x34"~ // frameCount
		"\x40\x00"~ // ShowFrame
		"\x40\x00"~ // ShowFrame
		"\x40\x00"~ // ShowFrame
		"\x00\x00"~ // End
		"";

	ubyte[] comp = compress2(movie);

	auto headIn = comp[0..LzmaHeader.sizeof].as!LzmaHeader;
	comp = comp[LzmaHeader.sizeof..$];

	auto headOut = SwfLzmaExtraData(
		cast(uint)comp.length,
		headIn.properties,
		headIn.dictionarySize);

	auto sr = SwfReader();
	sr.initialize();
	sr.put("ZWS\x01");
	sr.put(uint(8+cast(uint)movie.length).asBytes);
	sr.put(headOut.asBytes);
	sr.put(comp);
	sr.putEndOfInput();
	assert(!sr.hasErrors);

	SwfTag tag;
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 1);
	assert(!tag.data.length);
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 1);
	assert(!tag.data.length);
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 1);
	assert(!tag.data.length);
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 0);
	assert(!tag.data.length);
	if (sr.readTag(tag)) assert(0);

	assert(!sr.hasErrors);
}

// empty file with:
// - swf data past end tag (swf junk)
// - file data past header size (eof junk)
unittest
{
	auto sr = SwfReader();
	sr.initialize();
	sr.put("FWS\x01");
	sr.put(uint(21).asBytes);
	sr.put("\x00"); // rect
	sr.put("\x00\x00"); // frameRate
	sr.put("\x00\x00"); // frameCount
	sr.put("\x40\x00"); // ShowFrame
	sr.put("\x40\x00"); // ShowFrame
	sr.put("\x00\x00"); // End
	sr.put("\x01\x02"); // swf junk (included in header size)
	sr.put("\x03\x04"); // eof junk (past header size)
	sr.putEndOfInput();

	assert(sr.swfData.getReader.data == "\x40\x00\x40\x00\x00\x00\x01\x02");
	assert(sr.swfData.junkData[] == "\x03\x04");

	SwfTag tag;
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 1);
	assert(!tag.data.length);
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 1);
	assert(!tag.data.length);
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 0);
	assert(!tag.data.length);
	if (sr.readTag(tag)) assert(0);

	assert(sr.getUnusedSwfData[] == "\x01\x02");
	assert(sr.getCompressedJunkData[] == "");
	assert(sr.getEofJunkData[] == "\x03\x04");

	assert(!sr.hasErrors);
}

// compressed swf with
// - unused swf data included in header size
// - unused decompressed data not included in header size
// - unused file data past compressed body
unittest
{
	auto sr = SwfReader();
	sr.initialize();
	sr.put("CWS\x01");
	sr.put(uint(21).asBytes);
	sr.put(compress(
		"\x00"~     // rect
		"\xab\xcd"~ // frameRate
		"\x12\x34"~ // frameCount
		"\x40\x00"~ // ShowFrame
		"\x40\x00"~ // ShowFrame
		"\x00\x00"~ // End
		"\x01\x02"~ // swf junk (included in header size)
		"\x03\x04"  // swf junk (included in compressed body but not header size)
	));
	sr.put("\x05\x06"); // eof junk
	sr.putEndOfInput();
	assert(!sr.hasErrors);

	assert(sr.movieHeader.frameRate[0] == 0xab);
	assert(sr.movieHeader.frameRate[1] == 0xcd);
	assert(sr.movieHeader.frameCount == 0x3412);

	assert(sr.swfData.getReader.data == "\x40\x00\x40\x00\x00\x00\x01\x02");
	assert(sr.swfData.junkData[] == "\x03\x04");

	SwfTag tag;
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 1);
	assert(!tag.data.length);
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 1);
	assert(!tag.data.length);
	if (!sr.readTag(tag)) assert(0);
	assert(tag.code == 0);
	assert(!tag.data.length);
	if (sr.readTag(tag)) assert(0);

	assert(sr.getUnusedSwfData[] == "\x01\x02");
	assert(sr.getCompressedJunkData[] == "\x03\x04");
	assert(sr.getEofJunkData[] == "\x05\x06");

	assert(!sr.hasErrors);
}

// fileOffset (uncompressed)
unittest
{
	auto sr = SwfReader();
	sr.initialize();
	sr.put("FWS\x01");
	sr.put(uint(21).asBytes);
	sr.put("\x00"); // rect
	sr.put("\xab\xcd"); // frameRate
	sr.put("\x12\x34"); // frameCount
	sr.put("\x40\x00"); // ShowFrame
	sr.put("\x40\x00"); // ShowFrame
	sr.put("\x00\x00"); // End
	sr.putEndOfInput();

	SwfTag tag;
	if (!sr.readTag(tag)) assert(0); assert(tag.fileOffset == 13);
	if (!sr.readTag(tag)) assert(0); assert(tag.fileOffset == 15);
	if (!sr.readTag(tag)) assert(0); assert(tag.fileOffset == 17);
	if (sr.readTag(tag)) assert(0);

	assert(!sr.hasErrors);
}

// fileOffset (compressed)
unittest
{
	auto sr = SwfReader();
	sr.initialize();
	sr.put("CWS\x01");
	sr.put(uint(21).asBytes);
	sr.put(compress(
		"\x00"~     // rect
		"\xab\xcd"~ // frameRate
		"\x12\x34"~ // frameCount
		"\x40\x00"~ // ShowFrame
		"\x40\x00"~ // ShowFrame
		"\x00\x00"  // End
	));
	sr.putEndOfInput();

	SwfTag tag;
	if (!sr.readTag(tag)) assert(0); assert(tag.fileOffset == 13);
	if (!sr.readTag(tag)) assert(0); assert(tag.fileOffset == 15);
	if (!sr.readTag(tag)) assert(0); assert(tag.fileOffset == 17);
	if (sr.readTag(tag)) assert(0);

	assert(!sr.hasErrors);
}

/**
 * cast byte array to struct
 */
T as(T)(scope const(ubyte)[] data)
if (__traits(getPointerBitmap, T) == [T.sizeof, 0]) // no pointers
{
	assert(data.length == T.sizeof);
	return *cast(T*)data.ptr;
}

/**
 * cast struct to byte array
 */
auto ref inout(ubyte)[T.sizeof] asBytes(T)(return auto ref inout(T) val)
if (__traits(getPointerBitmap, T) == [T.sizeof, 0]) // no pointers
{
	return *cast(ubyte[T.sizeof]*)&val;
}
