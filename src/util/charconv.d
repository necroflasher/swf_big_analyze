module swfbiganal.util.charconv;

import core.stdc.errno;
import swfbiganal.cdef.iconv;
import swfbiganal.util.appender;

/**
 * convert string `s` encoded in charset `from` to charset `to`
 * 
 * params:
 *   s      string to convert
 *   from   source charset name
 *   to     destination charset name
 * 
 * returns:
 *   version of `s` encoded in the new charset, or null on error
 */

bool transmute(A)(
	scope const(void)[] s,
	const(char)*        from,
	const(char)*        to,
	ref A               ap)
{
	int err = dconv(s, from, to, (scope ubyte[] bytes, bool last)
	{
		ap ~= cast(typeof(ap[]))bytes;
		return 0;
	});

	return !err;
}

bool transmute(
	scope const(void)[] s,
	const(char)*        from,
	const(char)*        to,
	scope void delegate(scope const(void)[]) cb)
{
	ScopedAppender!(ubyte[]) ap;

	int err = dconv(s, from, to, (scope ubyte[] bytes, bool last)
	{
		if (last && !ap[].length && cb)
		{
			cb(bytes);
			cb = null;
		}
		else
		{
			ap ~= bytes;
		}
		return 0;
	});

	if (err)
	{
		return false;
	}

	if (cb)
	{
		cb(ap[]);
	}

	return true;
}

struct CharConv
{
	iconv_t cd;

	@disable this(this);

	bool initialize(const(char)* from, const(char)* to)
	{
		assert(cd == iconv_t.init);

		cd = iconv_open(to, from); // reversed order

		if (cd == -1)
		{
			cd = iconv_t.init;
			return false;
		}

		assert(cd != iconv_t.init);

		return true;
	}

	void finish()
	{
		assert(cd != iconv_t.init);

		iconv_close(cd);
		cd = iconv_t.init;
	}

	void reset()
	{
		void[32] buf = void;
		size_t inLength  = 0;
		void*  outPtr    = buf.ptr;
		size_t outLength = buf.length;
		iconv(cd, null, &inLength, &outPtr, &outLength);
	}

	bool put(
		scope const(void)[] input,
		scope void delegate(scope const(void)[]) cb)
	{
		void[512] buf = void;

		assert(cd != iconv_t.init);

		static if (0)
		{{
			auto tmpInput = input;
			import core.stdc.stdio;
			import swfbiganal.util.explainbytes;
			explainBytes(cast(ubyte[])tmpInput, (scope exp)
			{
				fprintf(stderr, "iconv call input=%.*s (%zu)\n", cast(int)exp.length, exp.ptr, tmpInput.length);
			});
		}}

		for (;;)
		{
			const(void)* inPtr     = input.ptr;
			size_t       inLength  = input.length;

			void*        outPtr    = buf.ptr;
			size_t       outLength = buf.length;

			if (!inLength)
			{
				return true;
			}

			size_t rv = iconv(cd, &inPtr, &inLength, &outPtr, &outLength);

			static if (0)
			{{
				auto tmpInput = input[0..inPtr-input.ptr];
				auto tmpOutput = buf[0..outPtr-buf.ptr];
				import core.stdc.stdio;
				import swfbiganal.util.explainbytes;
				explainBytes(cast(ubyte[])tmpInput, (scope exp)
				{
					fprintf(stderr, "iconv input=%.*s (%zu)\n", cast(int)exp.length, exp.ptr, tmpInput.length);
				});
				explainBytes(cast(ubyte[])tmpOutput, (scope exp)
				{
					fprintf(stderr, "iconv output=%.*s (%zu) - %.*s\n", cast(int)exp.length, exp.ptr, tmpOutput.length,
						cast(int)tmpOutput.length, cast(char*)tmpOutput.ptr);
				});
			}}

			if (rv == -1)
			{
				static if (0)
				{
					if (!(
						outPtr == buf.ptr ||
						outLength == buf.length ||
						inPtr == input.ptr ||
						inLength == input.length
					))
					{
						auto tmpInput = input[0..inPtr-input.ptr];
						auto tmpOutput = buf[0..outPtr-buf.ptr];
						import core.stdc.stdio;
						import swfbiganal.util.explainbytes;
						fprintf(stderr, "iconv errno=%d\n", errno);
						explainBytes(cast(ubyte[])tmpInput, (scope exp)
						{
							fprintf(stderr, "iconv input=%.*s (%zu)\n", cast(int)exp.length, exp.ptr, tmpInput.length);
						});
						explainBytes(cast(ubyte[])tmpOutput, (scope exp)
						{
							fprintf(stderr, "iconv output=%.*s (%zu)\n", cast(int)exp.length, exp.ptr, tmpOutput.length);
						});
						assert(0);
					}
				}
				// http://127.1.1.1/dbtest.php?do=analyze&md5=BB52AC63B9844AB80026ABD4A5F233DD
				// didn't write anything
				//assert(outPtr == buf.ptr);
				//assert(outLength == buf.length);
				// didn't skip anything
				//assert(inPtr == input.ptr);
				//assert(inLength == input.length);
				return false;
			}

			if (outPtr > buf.ptr)
			{
				cb(buf[0..outPtr-buf.ptr]);
			}

			input = inPtr[0..inLength];
		}
	}
}

// TEST
string transmute2(scope const(void)[] bytes, scope const(char)* encoding)
{
	ScopedAppender!(char[]) ap;
	CharConv conv;
	conv.initialize(encoding, "UTF-8");
	conv.put(bytes, (scope b) { ap ~= cast(char[])b; });
	conv.finish();
	return ap[].idup;
}

// -----------------------------------------------------------------------------

private:

int dconv(
	scope const(void)[] s,
	const(char)*        from,
	const(char)*        to,
	scope int delegate(scope ubyte[], bool) cb)
{
	iconv_t cd = iconv_open(to, from); // reversed order

	if (cd == -1)
		return errno;

	int err;

	const(void)* inbuf = s.ptr;
	size_t insz = s.length;
	while (insz && !err)
	{
		ubyte[512] buf = void;
		void* outbuf = buf.ptr;
		size_t outsz = buf.length;
		if (iconv(cd, &inbuf, &insz, &outbuf, &outsz) == -1 && outbuf == buf.ptr)
		{
			err = errno;
		}
		else
		{
			err = cb(buf[0..buf.length-outsz], !insz);
		}
	}

	iconv_close(cd);

	return err;
}

// -----------------------------------------------------------------------------

// old version that returns a GC string
version(unittest) void[] transmute(scope const(void)[] s, const(char)* from, const(char)* to)
{
	import std.array : Appender; // grep: unittest

	Appender!(ubyte[]) ap;

	int err = dconv(s, from, to, (scope ubyte[] bytes, bool last)
	{
		ap ~= bytes;
		return 0;
	});

	if (err)
	{
		return null;
	}

	ubyte[] str = ap[];
	if (!str.ptr)
	{
		static immutable ubyte[0] empty;
		str = cast(ubyte[])empty;
	}
	return str;
}

unittest
{
	{
		static immutable ubyte[] b = [0x81, 0x5b];
		assert(cast(char[])transmute(b, "shift_jis", "utf-8") == "ー");
	}

	{
		static immutable ubyte[] b = ['h', 0, 'i', 0];
		assert(cast(char[])transmute(b, "utf-16le", "utf-8") == "hi");
	}

	// bad utf-8
	{
		static immutable ubyte[] b = ['h', 0xff, 'i'];
		errno = 0;
		assert(cast(char[])transmute(b, "utf-8", "utf-16le") is null);
		assert(errno == EILSEQ);
	}
	{
		// it still converts 'h'
		static immutable ubyte[] b = ['h', 0xff, 'i'];
		ubyte[][] parts;
		int err = dconv(b, "utf-8", "utf-16le", (buf, last)
		{
			parts ~= buf.dup;
			return 0;
		});
		assert(err == EILSEQ);
		assert(parts == [['h', 0]]);
	}

	// this is a different errno from bad utf-8
	{
		static immutable ubyte[] b = ['h', 0, 'i'];
		errno = 0;
		assert(cast(char[])transmute(b, "utf-16le", "utf-8") is null);
		assert(errno == EINVAL);
	}

	static immutable ubyte[5*1024] buf = 'a';
	size_t bytesOut;

	bytesOut = 0;
	dconv(buf[], "CP936", "UTF-8", (scope ubyte[] buf, bool last)
	{
		bytesOut += buf.length;
		return 0;
	});
	assert(bytesOut == buf.length);

	foreach (bytesIn; [
		32,         // fits in stack buffer
		buf.length, // larger than stack buffer
		0,          // empty, should still call the callback
	])
	{
		bytesOut = 0;
		size_t count;
		if (!transmute(buf[0..bytesIn], "CP936", "UTF-8", (scope const(void)[] buf)
		{
			bytesOut += buf.length;
			count++;
		}))
			assert(0);
		assert(bytesOut == bytesIn);
		assert(count == 1);
	}
}
