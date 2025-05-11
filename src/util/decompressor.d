module swfbiganal.util.decompressor;

import core.stdc.stdio;
import core.stdc.string;
import etc.c.zlib;
import swfbiganal.cdef.lzma;
import swfbiganal.globals;
import swfbiganal.util.compiler;

union AnyDecomp
{
	Decomp     base;
	NullDecomp null_;
	ZlibDecomp zlib;
	LzmaDecomp lzma;
}

struct Decomp
{
	struct Funcs
	{
		int function(scope ref const(ubyte)[], scope int delegate(scope const(ubyte)[])) put;
		void function() deinitialize;
		const(char)* function(int) strerror;
		const(char)* function() type;
		size_t classSize;
	}

	// updated by .put() implementation
	ulong bytesIn;
	ulong bytesOut;

	private Funcs funcs;

	private void initializeFrom(T)(ref T cls)
	if (
		is(typeof(T.base) == Decomp) &&
		T.base.offsetof == 0 &&
		T.sizeof >= 1 && T.sizeof <= AnyDecomp.sizeof &&
		__traits(isZeroInit, T))
	{
		assert(!funcs.classSize);
		funcs.put = (&cls.put).funcptr;
		funcs.deinitialize = (&cls.deinitialize).funcptr;
		funcs.strerror = &cls.strerror;
		funcs.type = &cls.type;
		funcs.classSize = T.sizeof;
	}

	int put(scope ref const(ubyte)[] inbuf, scope int delegate(scope const(ubyte)[]) cb)
	in (funcs.put)
	in (inbuf.length)
	in (cb)
	{
		typeof(&put) fp;
		fp.ptr = &this;
		fp.funcptr = funcs.put;
		return fp(inbuf, cb);
	}

	void deinitialize()
	{
		if (funcs.deinitialize)
		{
			typeof(&deinitialize) fp;
			fp.ptr = &this;
			fp.funcptr = funcs.deinitialize;
			fp();
		}
		if (funcs.classSize)
		{
			memset(&this, 0, funcs.classSize);
		}
	}

	@cold
	const(char)* strerror(int code)
	in (funcs.strerror)
	{
		return funcs.strerror(code);
	}

	@cold
	const(char)* type()
	in (funcs.type)
	{
		return funcs.type();
	}
}

struct NullDecomp
{
	Decomp base;

	bool initialize()
	{
		base.initializeFrom(this);
		return true;
	}

	/**
	 * decompress some data
	 * 
	 * the input buffer is taken by reference and is updated to advance it past the data that was read
	 * - if the entire buffer was consumed and more data is expected, it's set to null
	 * - if decompression is finished, the buffer is advanced past the read data and will have a non-null .ptr
	 * 
	 * the return value is a compressor-dependent error code (always 0 on success), or a non-zero value returned from the callback
	 */
	int put(scope ref const(ubyte)[] inbuf, scope int delegate(scope const(ubyte)[]) cb)
	{
		base.bytesIn += inbuf.length;
		base.bytesOut += inbuf.length;
		int rv = cb(inbuf);
		inbuf = null;
		return rv;
	}

	void deinitialize()
	{
	}

	@cold
	static const(char)* strerror(int)
	{
		return "unknown";
	}

	@cold
	static const(char)* type()
	{
		return "null";
	}
}

struct ZlibDecomp
{
	Decomp base;
	z_stream zs;

	bool initialize()
	{
		int zerr = inflateInit(&zs);
		if (expect(zerr != Z_OK, false))
		{
			fprintf(stderr, "swfreader: inflateInit: %s (%d)\n", zError(zerr), zerr);
			return false;
		}
		base.initializeFrom(this);
		return true;
	}

	void deinitialize()
	{
		inflateEnd(&zs);
	}

	int put(scope ref const(ubyte)[] inbuf, scope int delegate(scope const(ubyte)[]) cb)
	{
		align(16) ubyte[GlobalConfig.DecompressBufferSize] outbuf = void;

		for (;;)
		{
			zs.next_out = outbuf.ptr;
			zs.avail_out = outbuf.length;

			zs.next_in = inbuf.ptr;
			zs.avail_in = cast(uint)inbuf.length;

			if (inbuf.length > uint.max)
				zs.avail_in = uint.max;

			int zerr = inflate(&zs, /* flush */ 0);

			size_t inlen = (zs.next_in - inbuf.ptr);
			size_t outlen = (zs.next_out - outbuf.ptr);

			//fprintf(stderr, "-zlib: rv=%d in=%zu out=%zu\n", zerr, inlen, outlen);

			base.bytesIn += inlen;
			base.bytesOut += outlen;
			//fprintf(stderr, "-total: in=%llu out=%llu\n", bytesIn, bytesOut);

			inbuf = inbuf[inlen..$];

			// cancelled
			if (int uerr = cb(outbuf[0..outlen]))
				return uerr;

			// error
			if (zerr != Z_OK && zerr != Z_STREAM_END)
				return zerr;

			// end of output
			if (zerr == Z_STREAM_END)
				return Z_OK;

			// end of input (need more data)
			if (!inbuf.length)
			{
				inbuf = null;
				return Z_OK;
			}
		}
	}

	@cold
	static const(char)* strerror(int zerr)
	{
		return zError(zerr);
	}

	@cold
	static const(char)* type()
	{
		return "zlib";
	}
}

struct LzmaDecomp
{
	Decomp base;
	lzma_stream lz;

	bool initialize()
	{
		lzma_ret ret = lzma_alone_decoder(&lz, /* memoryLimit */ ulong.max);
		if (expect(ret != lzma_ret.OK, false))
		{
			const(char)* errmsg = this.strerror(ret);
			fprintf(stderr, "swfreader: lzma_alone_decoder: %s (%d)\n", errmsg, ret);
			return false;
		}
		base.initializeFrom(this);
		return true;
	}

	void deinitialize()
	{
		lzma_end(&lz);
	}

	int put(scope ref const(ubyte)[] inbuf, scope int delegate(scope const(ubyte)[]) cb)
	{
		align(16) ubyte[GlobalConfig.DecompressBufferSize] outbuf = void;

		for (;;)
		{
			lz.next_out = outbuf.ptr;
			lz.avail_out = outbuf.length;

			lz.next_in = inbuf.ptr;
			lz.avail_in = inbuf.length;

			lzma_ret ret = lzma_code(&lz, lzma_action.RUN);

			size_t inlen = (lz.next_in - inbuf.ptr);
			size_t outlen = (lz.next_out - outbuf.ptr);

			base.bytesIn += inlen;
			base.bytesOut += outlen;

			inbuf = inbuf[inlen..$];

			// cancelled
			if (int uret = cb(outbuf[0..outlen]))
				return uret;

			// error
			if (ret != lzma_ret.OK && ret != lzma_ret.STREAM_END)
				return ret;

			// end of output
			if (ret == lzma_ret.STREAM_END)
				return lzma_ret.OK;

			// end of input (need more data)
			if (!inbuf.length)
			{
				inbuf = null;
				return lzma_ret.OK;
			}
		}
	}

	@cold
	static const(char)* strerror(int ret)
	{
		// descriptions from <lzma/base.h>
		static immutable char*[lzma_ret.max+1] txt = [
			lzma_ret.OK:                "Operation completed successfully",
			lzma_ret.STREAM_END:        "End of stream was reached",
			lzma_ret.NO_CHECK:          "Input stream has no integrity check",
			lzma_ret.UNSUPPORTED_CHECK: "Cannot calculate the integrity check",
			lzma_ret.GET_CHECK:         "Integrity check type is now available",
			lzma_ret.MEM_ERROR:         "Cannot allocate memory",
			lzma_ret.MEMLIMIT_ERROR:    "Memory usage limit was reached",
			lzma_ret.FORMAT_ERROR:      "File format not recognized",
			lzma_ret.OPTIONS_ERROR:     "Invalid or unsupported options",
			lzma_ret.DATA_ERROR:        "Data is corrupt",
			lzma_ret.BUF_ERROR:         "No progress is possible",
			lzma_ret.PROG_ERROR:        "Programming error",
		];
		immutable(char)* s = "unknown";
		if (ret >= 0 && ret < txt.length)
		{
			s = txt[ret];
		}
		return s;
	}

	@cold
	static const(char)* type()
	{
		return "lzma";
	}
}
