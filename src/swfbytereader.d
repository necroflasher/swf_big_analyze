module swfbiganal.swfbytereader;

import core.stdc.string : memchr;

/**
 * This is a simplified version of SwfBitReader that deals with bytes instead
 * of bits. It's meant as a potentially faster drop-in replacement for cases
 * that don't need bit-level access.
 */

struct SwfByteReader
{
	const(ubyte)[] data;
	size_t         curByte;
	bool           overflow;

	invariant(!overflow ? (curByte <= data.length) : (curByte == data.length));

	this(const(ubyte)[] data_)
	{
		data = data_;
	}

	bool empty() const
	{
		return curByte == data.length;
	}

	size_t bytesLeft() const
	{
		return data.length - curByte;
	}

	const(ubyte)[] readBytesNoCopy(size_t count)
	{
		if (count ? bytesLeft >= count : !overflow)
		{
			const(ubyte)[] b = data[curByte..curByte+count];
			curByte += count;
			return b;
		}
		else
		{
			curByte = data.length;
			overflow = true;
			return null;
		}
	}
	unittest
	{
		ubyte[1] bs = [1];
		auto br = SwfByteReader(bs);
		assert(br.readBytesNoCopy(1) == [1]);   assert(br.curByte == 1 && !br.overflow);
		assert(br.readBytesNoCopy(0) == []);    assert(br.curByte == 1 && !br.overflow);
		assert(br.readBytesNoCopy(0) !is null); assert(br.curByte == 1 && !br.overflow);
		br.curByte = 0;
		assert(br.readBytesNoCopy(2) is null); assert(br.curByte == 1 && br.overflow);
		assert(br.readBytesNoCopy(0) is null); assert(br.curByte == 1 && br.overflow);
	}

	const(ubyte)[] readRemaining()
	{
		if (!overflow)
		{
			const(ubyte)[] b = data[curByte..$];
			curByte = data.length;
			return b;
		}
		else
		{
			curByte = data.length;
			overflow = true;
			return null;
		}
	}

	const(ubyte)[] remaining() const
	{
		return !overflow ? data[curByte..$] : null;
	}

	void skip(T)()
	{
		skipBytes(T.sizeof);
	}

	void skipBytes(size_t count)
	{
		if (bytesLeft >= count)
		{
			curByte += count;
		}
		else
		{
			curByte = data.length;
			overflow = true;
		}
	}

	// bit of a misfeature but sometimes the bit count is more natural to write
	// this better be called with a constant value
	void skipBits(uint count)
	{
		assert(count%8 == 0);
		skipBytes(count/8);
	}

	const(ubyte)[] readNullTerminatedBytes()
	{
		const(ubyte)[] str;

		const(void)[] rem = data[curByte..$];
		if (const(void)* p = memchr(rem.ptr, '\0', rem.length))
		{
			size_t length = (p - rem.ptr);
			str = data[curByte..curByte+length];
			curByte += 1+length;
		}
		else
		{
			curByte = data.length;
			overflow = true;
		}

		return str;
	}

	const(char)[] readNullTerminatedUtf8()
	{
		return cast(char[])readNullTerminatedBytes();
	}

	uint read(T)()
	if (is(T == ulong) || is(T == uint) || is(T == ushort))
	{
		if (bytesLeft >= T.sizeof)
		{
			size_t pos = curByte;
			curByte += T.sizeof;
			union U
			{
				T               i = void;
				ubyte[T.sizeof] b = void;
			}
			U u = void;
			u.b = data[pos..pos+T.sizeof];
			return u.i;
		}
		else
		{
			curByte = data.length;
			overflow = true;
			return 0;
		}
	}

	uint read(T)()
	if (is(T == ubyte))
	{
		if (curByte < data.length)
		{
			return data[curByte++];
		}
		else
		{
			curByte = data.length;
			overflow = true;
			return 0;
		}
	}

	// might be unnecessary, doubt this would be dynamically sized
	deprecated("unused? (remove deprecation if used)")
	uint readUI(uint bits)
	{
		if (bits == 32) return read!uint;
		if (bits == 16) return read!ushort;
		if (bits == 8)  return read!ubyte;
		assert(0);
	}
	deprecated unittest
	{
		ubyte[5] bs = [0xaa, 0xbb, 0xcc, 0xdd, 0xee];
		auto br = SwfByteReader(bs);
		assert(br.readUI(8) == 0xaa);
		assert(br.readUI(8) == 0xbb);
		br.curByte = 0;
		assert(br.readUI(16) == 0xbbaa);
		assert(br.readUI(16) == 0xddcc);
		br.curByte = 0;
		assert(br.readUI(32) == 0xddccbbaa);
		assert(br.readUI(8) == 0xee);
		assert(!br.overflow);
		assert(br.readUI(8) == 0);
		assert(br.overflow);
		assert(br.readUI(8) == 0);
		assert(br.overflow);
	}
}

private:

auto min(A, B)(A a, B b)
if (is(A == B))
{
	if (b < a) a = b;
	return a;
}
