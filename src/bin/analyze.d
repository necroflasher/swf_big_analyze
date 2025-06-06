module swfbiganal.bin.analyze;

import core.stdc.errno;
import core.stdc.stdio;
import core.stdc.string;
import core.sys.posix.fcntl;
import core.sys.posix.unistd;
import core.memory;
import core.runtime; // grep: unavoidable
import etc.c.zlib;
import swfbiganal.globals;
import swfbiganal.swfreader;
import swfbiganal.swftypes.swftag;
import swfbiganal.swftypes.swfheader;
import swfbiganal.swftypes.swflzmaextradata;
import swfbiganal.swf.errors;
import swfbiganal.swf.tags;
import swfbiganal.swf.tagtimestat;
import swfbiganal.util.commaize;
import swfbiganal.util.compiler;
import swfbiganal.util.explainbytes;
import swfbiganal.util.urlencode;
import swfbiganal.util.string;
import core.bitop : bswap;

private:

extern (C) __gshared string[] rt_options = [
	"gcopt=cleanup:none",

	// https://dlang.org/spec/garbage.html#gc_config
	// at the time of writing, the biggest GC size in a single flash is one of
	//  the furry text adventure games at 13,259,760 bytes
	"gcopt=minPoolSize:8",   // "initial and minimum pool size in MB"
	"gcopt=maxPoolSize:256", // "maximum pool size in MB"
	"gcopt=incPoolSize:8",   // "pool size increment MB"

	// must be last - filtered out by command line
	"gcopt=profile:1",
];
// not used, might save a bit of time
extern (C) __gshared bool rt_envvars_enabled = false;
extern (C) __gshared bool rt_cmdline_enabled = false;

version(DigitalMars)
{
	enum EXENAME = "analyze";
}
else version(LDC)
{
	enum EXENAME = "analyze2";
}
else version(GNU)
{
	enum EXENAME = "analyze3";
}

extern(C) int main(int argc, char** argv)
{
	TagTimeStat tagTimeStat;
	const(char)* currentSwfPath;
	const(char)* charset;
	int rv;
	bool useTagTimeStat;
	bool hasFiles;
	bool useProfileGc;
	bool disableGc;

	for (int i = 1; i < argc; i++)
	{
		if (argv[i][0] == '-')
		{
			char* opt = argv[i];
			argv[i] = null;

			if (!strncmp(opt, "-charset=", 9))
			{
				charset = opt+9;
			}
			else if (!strcmp(opt, "-gc"))
			{
				useProfileGc = true;
			}
			else if (!strcmp(opt, "-nogc"))
			{
				disableGc = true;
			}
			else if (!strcmp(opt, "-stat"))
			{
				useTagTimeStat = true;
			}
			else if (!strcmp(opt, "-tags"))
			{
				GlobalConfig.OutputTags = true;
			}
			else if (!strcmp(opt, "--"))
			{
				break;
			}
			else
			{
				fprintf(stderr, EXENAME~": unknown option '%s'\n", opt);
				rv = 1;
				goto endNoRt;
			}
		}
		else
		{
			continue;
		}
	}

	if (!useProfileGc)
	{
		// skip the bounds check (yolo)
		rt_options = rt_options.ptr[0..rt_options.length-1];
	}

	if (expect(!rt_init(), false))
	{
		rv = 1;
		goto endNoRt;
	}
	if (disableGc)
		GC.disable();

	version(unittest)
	{{
		auto result = runModuleUnitTests();
		rv = (result.passed == result.executed) ? 0 : 1;
		if (!rv)
		{
			printf("%zu modules passed unittests\n", result.passed);
		}
		goto end;
	}}

	try
	{
		for (int i = 1; i < argc; i++)
		{
			const(char)* path = argv[i];
			if (expect(!path, false))
			{
				continue;
			}

			hasFiles = true;

			int fd = open(path, O_RDONLY);
			if (expect(fd < 0, false))
			{
				fprintf(stderr, "open %s: %s\n", path, strerror(errno));
				rv = 1;
				continue;
			}

			stat_t sb = void;
			if (expect(fstat(fd, &sb) < 0, false))
			{
				fprintf(stderr, "stat %s: %s\n", path, strerror(errno));
				close(fd);
				rv = 1;
				continue;
			}

			currentSwfPath = path;

			ulong gcBefore = GC.stats().allocatedInCurrentThread;

			printFileLine(path, sb.st_size);

			bool swfReadOk = readSwf(
				fd,
				charset,
				useTagTimeStat ? &tagTimeStat : null,
				gcBefore,
			);

			if (expect(!swfReadOk, false))
			{
				rv = 1;
			}

			currentSwfPath = null;

			close(fd);
		}
	}
	catch (Throwable e)
	{
		// we don't use exceptions (on purpose)
		// they might still be generated by asserts and bounds checks
		// anyway, this just exists to print the filename for a bit of added convenience
		fprintf(stderr, "error processing file %s:\n", currentSwfPath);
		e.toString((in char[] buf)
		{
			fwrite(buf.ptr, 1, buf.length, stderr);
		});
		fputc('\n', stderr);
		_exit(1);
	}

	if (!hasFiles)
	{
		fprintf(stderr,
			"usage: "~EXENAME~" [options] <swf files>\n"~
			"options:\n"~
			"    -charset=<cs>  decode SWF1-5 text using charset (e.g. CP932)\n"~
			"    -gc            print gc profile data at exit\n"~
			"    -nogc          turn off garbage collection\n"~
			"    -stat          print time/space used parsing tags\n"~
			"    -tags          output a line for every encountered tag\n"~
			"");

		if (!rv)
			rv = 1;
	}

end:

	if (expect(useTagTimeStat, false))
		tagTimeStat.printTotals();

	if (expect(useProfileGc, false))
	{
		char[27] buf = void;
		fprintf(stderr, "GC total: %s bytes (overall)\n",
			GC.allocatedInCurrentThread().commaize(buf));
	}

	{
		// D runtime prints gc stats to stdout, make it go in stderr instead
		FILE* tmp;
		if (expect(useProfileGc, false))
		{
			tmp = stdout;
			stdout = stderr;
		}
		if (expect(!rt_term(), false))
		{
			if (!rv)
				rv = 1;
		}
		if (expect(useProfileGc, false))
			stdout = tmp;
	}

endNoRt:

	return rv;
}

bool readSwf(
	int          fd,
	const(char)* defaultCharset,
	TagTimeStat* ts,
	ulong        gcBefore)
{
	align(16) ubyte[GlobalConfig.ReadBufferSize] buf = void;

	auto sr = SwfReader();
	sr.initialize();

	TagParserState parserState = {
		reader:         &sr,
		defaultCharset: defaultCharset,
		tagTimeStat:    ts,
		tagPrintFunc:   &printTagLine,
	};

	SwfReader.State prevState;
	bool            gotEndTag;

	ulong totalBytesRead;

	for (;;)
	{
		ssize_t readrv = read(fd, buf.ptr, buf.length);

		if (expect(readrv < 0, false))
		{
			int err = errno;
			if (expect(err == EINTR, true))
			{
				continue;
			}
			perror("read");
			// make some noise
			assert(0);
		}

		if (expect(readrv != 0, true))
		{
			sr.put(buf[0..readrv]);
			totalBytesRead += readrv;
		}

		// check if the .put() just completed any headers
		if (sr.state != prevState)
		{
			if (prevState < SwfReader.State.readTagData)
			{
				printHeaderLines(sr, prevState, totalBytesRead);
			}
			prevState = sr.state;

			// bad header
			// it's fine to quit here, reading tags wouldn't do anything useful
			if (sr.hasErrors)
			{
				printEndOfFile(sr, gotEndTag, gcBefore);
				break;
			}
		}

		if (!readrv)
			sr.putEndOfInput();

		for (SwfTag tag = void; sr.readTag(tag); /* empty */)
		{
			if (expect(GlobalConfig.OutputTags, false))
			{
				printTagLine(tag);
			}
			static if (GlobalConfig.ParseTags)
			{
				readTag(parserState, tag, gotEndTag);
			}
		}

		// file just ended?
		if (!readrv)
		{
			printEndOfFile(sr, gotEndTag, gcBefore);
			break;
		}
	}

	if (sr.hasErrors)
		return false;

	return true;
}

void printHeaderLines(
	ref SwfReader   sr,
	SwfReader.State prevState,
	ulong           totalBytesRead)
{
	if (
		prevState <= SwfReader.State.readSwfHeader &&
		sr.state > SwfReader.State.readSwfHeader)
	{
		// don't print if it's incomplete
		if (totalBytesRead >= SwfHeader.sizeof)
		{
			printSwfHeaderLine(sr);
		}
		// exit here if the swf header isn't valid
		if (!sr.swfHeader.isValid)
		{
			return;
		}
	}

	if (
		prevState <= SwfReader.State.readCompressionHeader &&
		sr.state > SwfReader.State.readCompressionHeader)
	{
		if (sr.swfHeader.isCompressed)
		{
			printCompressionHeaderLine(sr);
		}
	}

	if (
		prevState <= SwfReader.State.readMovieHeader &&
		sr.state > SwfReader.State.readMovieHeader)
	{
		printMovieHeaderLine(sr);
	}
}

void printTagLine(ref const(SwfTag) tag)
{
	pragma(inline, true);
	Format!(4+20+1+1+1+20+1+8+1) fmt;
	fmt.append("tag ");
	fmt.appendUnsignedDecimal(tag.code);
	fmt.append(' ');
	fmt.append(tag.longFormat ? 'l' : 's');
	fmt.append(' ');
	fmt.appendUnsignedDecimal(tag.data.length);
	fmt.append(' ');
	fmt.appendHex8(crc32_z(0, tag.data.ptr, tag.data.length));
	fmt.append('\n');

	fwrite(fmt.buf.ptr, 1, fmt.i, stdout);
}

void printFileLine(const(char)* path, ulong filesize)
{
	urlEncodeMin(path.fromStringz, (scope s)
	{
		printf("file %llu %.*s\n",
			filesize,
			cast(int)s.length, s.ptr,
			);
	});
}

void printSwfHeaderLine(ref SwfReader sr)
{
	urlEncodeMin(sr.swfHeader.signature, (scope s)
	{
		printf("swf-header %.*s %hhu %u\n",
			cast(int)s.length, s.ptr,
			sr.swfHeader.swfVersion,
			sr.swfHeader.fileSize,
			);
	});
}

void printCompressionHeaderLine(ref SwfReader sr)
{
	if (sr.swfHeader.isZlibCompressed && sr.compressionHeader.length)
	{
		assert(sr.compressionHeader.length == 2 || sr.compressionHeader.length == 6);

		// https://www.rfc-editor.org/rfc/rfc1950
		uint method  = sr.compressionHeader[0] & 0b1111;
		uint info    = sr.compressionHeader[0] >> 4;
		uint check   = sr.compressionHeader[1] & 0b11111;
		uint usedict = (sr.compressionHeader[1] >> 5) & 1;
		uint level   = sr.compressionHeader[1] >> 6;

		// method: compression method - must be 8
		// info: window bits - must be 0-7, not sure if this affects decompression
		// check: any bits so that b[0]*256+b[1] % 31 == 0 (multiple allowed values)
		// usedict: 1 if a dictionary should be used, must be 0 since flash doesn't support this
		// level: compression level (0-3), doesn't affect decompression

		char[9] dict = "-";
		if (sr.compressionHeader.length == 6)
		{
			// adler checksum of dictionary to use (stored in network byte order)
			sprintf(dict.ptr, "%08x", bswap(*cast(uint*)sr.compressionHeader[2..6].ptr));
		}

		printf("zlib-header %u %u %u %c %u %s\n",
			method,
			info,
			check,
			usedict ? 'y' : 'n',
			level,
			dict.ptr,
			);
	}
	else if (sr.swfHeader.isLzmaCompressed && sr.compressionHeader.length)
	{
		assert(sr.compressionHeader.length == SwfLzmaExtraData.sizeof);

		auto lzma = cast(SwfLzmaExtraData*)sr.compressionHeader.ptr;
		printf("lzma-header %u %02hhx %x\n",
			lzma.lzmaBodySize,
			lzma.properties,
			lzma.dictionarySize,
			);
	}
	else
	{
		assert(0);
	}
}

void printMovieHeaderLine(ref SwfReader sr)
{
	printf("movie-header %u %d %d %d %d %02hhx-%02hhx %u\n",
		sr.movieHeader.display.bits,
		sr.movieHeader.display.xmin,
		sr.movieHeader.display.xmax,
		sr.movieHeader.display.ymin,
		sr.movieHeader.display.ymax,
		sr.movieHeader.frameRate[0],
		sr.movieHeader.frameRate[1],
		sr.movieHeader.frameCount,
		);
}

void printEndOfFile(
	ref SwfReader sr,
	bool          gotEndTag,
	ulong         gcBefore)
{
	if (expect(sr.hasErrors, false))
	{
		printf("errors %zu %zu\n",
			sr.softErrors.count,
			sr.hardErrors.count);

		foreach (e; sr.softErrors) printf("soft-error %s\n", e.toString);
		foreach (e; sr.hardErrors) printf("hard-error %s\n", e.toString);
	}

	// skip this data stuff if the file isn't swf
	if (expect(sr.swfHeader.isValid, true))
	{
		// unused swf data
		{
			char[4] type = "swf\0";
			if (!sr.swfHeader.isCompressed)
				type = "unc\0";
			if (gotEndTag)
				type[2] = 'e';

			const swfJunk = sr.getUnusedSwfData();
			if (swfJunk.total)
			{
				explainBytes(swfJunk.data, (scope exp)
				{
					printf("%s-junk-data %llu %08x %.*s\n",
						type.ptr,
						swfJunk.total,
						swfJunk.crc,
						cast(int)exp.length, exp.ptr,
						);
				});
			}
		}

		// overflow swf data
		{
			const overflowJunk = sr.getOverflowSwfData();
			if (overflowJunk.total)
			{
				explainBytes(overflowJunk.data, (scope exp)
				{
					printf("ovf-junk-data %llu %08x %.*s\n",
						overflowJunk.total,
						overflowJunk.crc,
						cast(int)exp.length, exp.ptr,
						);
				});
			}
		}

		// unused compressed data
		{
			const cmpJunk = sr.getCompressedJunkData();
			if (cmpJunk.total)
			{
				explainBytes(cmpJunk.data, (scope exp)
				{
					printf("cmp-junk-data %llu %08x %.*s\n",
						cmpJunk.total,
						cmpJunk.crc,
						cast(int)exp.length, exp.ptr,
						);
				});
			}
		}

		// data after compressed body
		{
			const eofJunk = sr.getEofJunkData();
			if (eofJunk.total)
			{
				explainBytes(eofJunk.data, (scope exp)
				{
					printf("eof-junk-data %llu %08x %.*s\n",
						eofJunk.total,
						eofJunk.crc,
						cast(int)exp.length, exp.ptr,
						);
				});
			}
		}

		// print swfData if we successfully parsed any of it
		if (sr.validSwfDataSize)
		{
			printf("swf-data-total %llu %08x\n",
				sr.validSwfDataSize,
				sr.validSwfDataCrc,
				);
		}
	}

	ulong gcNow = GC.stats().allocatedInCurrentThread;
	printf("gc-total %llu\n", gcNow-gcBefore);
}

// helper for formatting tag output with hihg performance
struct Format(size_t buflen)
{
	char[buflen] buf = void;
	size_t       i;

	void append(scope const(char)[] s)
	{
		pragma(inline, true);
		buf[i..i+s.length] = s;
		i += s.length;
	}

	void append(char c)
	{
		pragma(inline, true);
		buf[i++] = c;
	}

	void appendUnsignedDecimal(ulong val)
	{
		char[20] tmp = void;
		char* p = &tmp[$-1];
		do
		{
			*p-- = '0' + (val % 10);
			val /= 10;
		}
		while (val);
		size_t len = (&tmp[$-1] - p);
		append((p+1)[0..len]);
	}

	void appendHex8(uint val)
	{
		static immutable hexdigits = "0123456789abcdef";
		foreach (x, ref c; buf[i..i+8])
		{
			c = hexdigits[(val >> (7-x)*4) & 0xf];
		}
		i += 8;
	}
}

unittest
{
	assert({ Format!20 fmt; fmt.appendUnsignedDecimal(0); return fmt.buf[0..fmt.i].idup; }() == "0");
	assert({ Format!20 fmt; fmt.appendUnsignedDecimal(123); return fmt.buf[0..fmt.i].idup; }() == "123");
	assert({ Format!10 fmt; fmt.append('['); fmt.appendHex8(0x42); fmt.append(']'); return fmt.buf[0..fmt.i].idup; }() == "[00000042]");
	assert({ Format!8 fmt; fmt.appendHex8(0x42); return fmt.buf[0..fmt.i].idup; }() == "00000042");
	assert({ Format!8 fmt; fmt.appendHex8(0x42abcdef); return fmt.buf[0..fmt.i].idup; }() == "42abcdef");
}
