module swfbiganal.swfbitreader;

import core.stdc.string : memchr;
import swfbiganal.util.compiler;
import swfbiganal.util.tosigned;

public import swfbiganal.swfbytereader;

// On overflow, methods should return the .init of the type (0, null, or nan).

// Types to use for things:
// - Bit array length -> ulong
// - Byte array length -> size_t
// - Number of bits in a number -> uint

// 32bit
private size_t bitsToBytes(ulong bits)
{
	pragma(inline, true);
	return cast(size_t)(bits >> 3);
}

struct SwfBitReader
{
	const(ubyte)[] data;
	ulong          curBit;
	ulong          totalBits;
	bool           overflow;

	invariant
	{
		pragma(inline, true);
		assert(!overflow ? (curBit <= totalBits) : (curBit == totalBits));
	}

	this(const(ubyte)[] data_)
	in (data_.length <= ulong.max/8) // length*8 fits in ulong
	{
		data = data_;
		totalBits = cast(ulong)data_.length*8;
	}

	bool empty() const
	{
		return (curBit == totalBits);
	}

	ulong bitsLeft() const
	{
		return totalBits-curBit;
	}

	void byteAlign()
	{
		version (LDC)
		{
			while (curBit & 0b111)
			{
				curBit++;
			}
		}
		else
		{
			curBit = (curBit + 7) & ~0b111UL;
		}
	}

	void skipBytes(size_t countBytes)
	{
		ulong countBits = cast(ulong)countBytes*8;

		// byte-align
		while ((curBit+countBits) & 0b111)
			countBits++;

		if (expect(totalBits-curBit >= countBits, true))
		{
			curBit += countBits;
		}
		else
		{
			setOverflow();
		}
	}

	void skipBits(ulong count)
	{
		if (expect(totalBits-curBit >= count, true))
		{
			curBit += count;
		}
		else
		{
			setOverflow();
		}
	}

	const(ubyte)[] remaining() const
	{
		if (expect(!overflow, true))
		{
			return data[bitsToBytes(curBit + 7)..$];
		}
		else
		{
			return null;
		}
	}

	const(ubyte)[] readRemaining()
	{
		if (expect(!overflow, true))
		{
			ulong startBit = curBit;
			curBit = totalBits;
			return data[bitsToBytes(startBit + 7)..$];
		}
		else
		{
			return null;
		}
	}

	void skip(T)()
	if (is(T == uint) || is(T == ushort) || is(T == ubyte))
	{
		skipBytes(T.sizeof);
	}

	uint read(T)()
	if (is(T == uint) || is(T == ushort) || is(T == ubyte))
	{
		ulong startBit = curBit;

		// byte-align
		while (startBit & 0b111)
			startBit++;

		// check overflow
		if (expect(totalBits-startBit >= T.sizeof*8, true))
		{
			version(LDC)
			{
				// reassure the optimizer that the three low bits aren't set
				curBit = (startBit + T.sizeof*8) & ~0b111UL;
			}
			else
			{
				curBit = (startBit + T.sizeof*8);
			}

			const size_t readPos = cast(size_t)(startBit/8);

			version(DigitalMars)
			{
				union U
				{
					T               u = void;
					ubyte[T.sizeof] b = void;
				}
				U u = void;
				u.b = data[readPos..readPos+T.sizeof];
				return u.u;
			}
			else
			{
				// LDC: compiles to a single load
				uint rv;
				static foreach_reverse (i; 0..T.sizeof)
				{
					rv |= data[readPos+i]<<(i*8);
				}
				return rv;
			}
		}
		else
		{
			setOverflow();
			return 0;
		}
	}

	const(ubyte)[] readBytesNoCopy(size_t numBytes)
	{
		ulong nextPos = (curBit + 7 + numBytes*8) & ~0b111UL;
		if (nextPos <= totalBits && !overflow)
		{
			curBit = nextPos;
			size_t readPos = bitsToBytes(nextPos - numBytes*8);
			return data[readPos..readPos+numBytes];
		}
		else
		{
			setOverflow();
			return null;
		}
	}

	/**
	 * read a "U30" variable-length integer
	 * 
	 * https://web.archive.org/web/20220523173435/https://www.m2osw.com/mo_references_view/sswf_docs/abcFormat.html
	 * https://github.com/ruffle-rs/ruffle/blob/b6fd670410bdf34ca1b42cb34268ff2211c46e51/swf/src/extensions.rs#L74
	 */
	uint readU30()
	{
		byteAlign();

		const size_t curByte = bitsToBytes(curBit);
		const size_t end = min(data.length, curByte+5);

		uint rv;
		foreach (i, b; data[curByte..end])
		{
			rv |= (b & 0b0_1111111) << 7*i;
			if ((b & 0b1_0000000) == 0)
			{
				curBit = (curByte+i+1)*8;
				return rv;
			}
		}

		// if we got here, it means a byte without the top bit wasn't found
		// advance by 5 bytes to match what flash player presumably does

		// some obfuscated AS3 flashes need this to show strings:
		// http://127.1.1.1/dbtest.php?do=analyze&md5=19D1E32953A8D51777FECDC7ABE734C5
		// http://127.1.1.1/dbtest.php?do=analyze&md5=D68B09A6EC08E5CBAF47FFB25129DB0A
		// http://127.1.1.1/dbtest.php?do=analyze&md5=3CDE9062CD7234361DB6AB6BBE04321A
		// http://127.1.1.1/dbtest.php?do=analyze&md5=BAF533F6E324D71B55A080DB821C8EF2
		// http://127.1.1.1/dbtest.php?do=analyze&md5=62AA8BC4F069A3DB202E945081D0D6AB
		// http://127.1.1.1/dbtest.php?do=analyze&md5=33B709BCB107FC6C919F2E196F3C2697
		// http://127.1.1.1/dbtest.php?do=analyze&md5=CDD9CCEFDFB22B95A00E3ACFFC3ACCEF
		// http://127.1.1.1/dbtest.php?do=analyze&md5=D13DE0515E77A3B47A9DB92DB3978D2C

		// let's still check for size overflow

		ulong nextPos = curBit + 5*8;
		if (nextPos > totalBits)
		{
			setOverflow();
			return 0;
		}
		curBit = nextPos;
		return rv;
	}

	const(ubyte)[] readNullTerminatedBytes()
	{
		const(void)[] rem = data[bitsToBytes(curBit + 7)..$];
		const(void)* p = memchr(rem.ptr, '\0', rem.length);
		if (expect(p != null, true))
		{
			size_t length = (p - rem.ptr);
			// +7 and mask to byte-align the new pos
			curBit = (curBit + 7 + (length+1)*8) & ~0b111UL;
			return cast(ubyte[])rem[0..length];
		}
		else
		{
			setOverflow();
			return null;
		}
	}

	const(char)[] readNullTerminatedUtf8()
	{
		return cast(char[])readNullTerminatedBytes();
	}

	enum testSpecializeReadUB = true;

	static if (testSpecializeReadUB)
	{
		uint readUB(uint numbits)()
		if (numbits == 1)
		{
			if (expect(totalBits-curBit < numbits, false))
			{
				setOverflow();
				return 0;
			}

			uint rv = (data[bitsToBytes(curBit)] >> (~curBit & 0b111)) & 1;
			curBit += numbits;
			return rv;
		}

		uint readUB(uint numbits)()
		if (numbits >= 2 && numbits <= 8)
		{
			if (expect(totalBits-curBit < numbits, false))
			{
				setOverflow();
				return 0;
			}

			uint curByteBits = (~curBit & 0b111)+1; // bits left to read in curByte
			enum mask = ( 1 << numbits )-1;

			uint rv;
			if (curByteBits >= numbits)
			{
				rv = (data[bitsToBytes(curBit)] >> (curByteBits - numbits)) & mask;
			}
			else
			{
				rv = ((data[bitsToBytes(curBit)] << 8 | data[bitsToBytes(curBit)+1]) >> (curByteBits - (numbits-8))) & mask;
			}
			curBit += numbits;
			return rv;
		}
	}
	else
	{
		uint readUB(uint numbits)()
		{
			return readUB(numbits);
		}
	}

	unittest
	{
		struct T
		{
			ubyte[] bytes;
			ulong startpos;
			uint readbits;
			uint val;
		}
		static immutable T[] data = [
			T([0b10110011, 0b10001111], 0, 1, 0b1),
			T([0b10110011, 0b10001111], 0, 2, 0b10),
			T([0b10110011, 0b10001111], 0, 3, 0b101),
			T([0b10110011, 0b10001111], 4, 4, 0b0011),
			T([0b10110011, 0b10001111], 4, 5, 0b00111),
			T([0b10110011, 0b10001111], 4, 8, 0b00111000),
			T([0b10110011, 0b10001111], 7, 1, 0b1),
			T([0b10110011, 0b10001111], 7, 2, 0b11),
			T([0b10110011, 0b10001111], 7, 7, 0b1100011),
			T([0b10110011, 0b10001111], 7, 8, 0b11000111),
			T([0b11111111, 0b00000000], 7, 1, 0b1),
			T([0b00000000, 0b11111111], 7, 1, 0b0),
			T([0b11111111], 7, 1, 0b1),
			T([0b00000000], 7, 1, 0b0),
			T([0b11111111], 6, 1, 0b1),
			T([0b00000000], 6, 1, 0b0),
			T([0b11111111], 6, 2, 0b11),
			T([0b00000000], 6, 2, 0b00),
		];
		foreach (ref t; data)
		{
			auto br = SwfBitReader(t.bytes);
			br.curBit = t.startpos;
			uint val = br.readUB(t.readbits);
			assert(val == t.val);
			assert(br.curBit == t.startpos+t.readbits);
		}
	}

	uint readUB(uint numbits)
	{
		version(unittest)
		{
			static if (testSpecializeReadUB)
			{
				static foreach (i; 1..8+1)
				{
					if (numbits == i)
					{
						return readUB!i;
					}
				}
			}
		}

		if (expect(totalBits-curBit < numbits, false))
		{
			setOverflow();
			return 0;
		}

		uint rv;
		while (numbits)
		{
			uint curByteBits = 8 - (curBit & 0b111); // bits left in curByte
			uint wantBits = min(curByteBits, numbits); // how many we'll use
			uint mask = ( 1 << wantBits )-1;

			rv <<= wantBits;
			rv |= (data[bitsToBytes(curBit)] >> (curByteBits - wantBits)) & mask;

			curBit += wantBits;
			numbits -= wantBits;
		}
		return rv;
	}
	unittest
	{
		ubyte[4] bs = [42, 0b1100_0101, 0xde, 0xad];
		auto br = SwfBitReader(bs);
		assert(br.readUB(8) == 42);
		assert(br.readUB(2) == 0b11);
		assert(br.readUB(2) == 0b00);
		assert(br.readUB(4) == 0b0101);
		assert(br.readUB(16) == 0xdead);
		br.curBit -= 16;
		assert(br.read!ushort == 0xadde); // got to be careful with this
		br.curBit = 8;
		assert(br.readUB(1) == 0b1);
		assert(br.readUB(1) == 0b1);
		assert(br.readUB(1) == 0b0);
		assert(br.readUB(1) == 0b0);
	}

	int readSB(uint numbits)
	{
		return readUB(numbits).toSigned(numbits);
	}

	@cold
	void setOverflow()
	{
		pragma(inline, true);
		overflow = true;
		curBit = totalBits;
	}
}

private:

auto min(A, B)(A a, B b)
if (is(A == B))
{
	if (b < a) a = b;
	return a;
}

version(unittest)
auto readASConstantString(ref SwfBitReader br)
{
	return cast(char[])br.readBytesNoCopy(br.readU30());
}

version(unittest)
auto readUI(ref SwfBitReader br, uint bits)
{
	if (bits == 32) return br.read!uint;
	if (bits == 16) return br.read!ushort;
	if (bits == 8) return br.read!ubyte;
	assert(0);
}

unittest
{
	ubyte[3] bs = [1,2,3];
	SwfBitReader br;
	br = SwfBitReader(bs);
	assert(br.readBytesNoCopy(3) == bs);
	assert(br.readBytesNoCopy(0) !is null); // 0 -> non-null if !overflow
	assert(br.readBytesNoCopy(3) is null);
	assert(br.readBytesNoCopy(0) is null); // 0 -> null if overflow
}

unittest
{
	ubyte[4] bs = [1,2,3,4];
	auto br = SwfBitReader(bs);
	assert(br.readBytesNoCopy(1) == [1]);
	br.curBit = 0;
	assert(br.readBytesNoCopy(4) == [1,2,3,4]);
	br.curBit = 0;
	assert(br.readBytesNoCopy(5) is null);
	br.overflow = false; br.curBit = 1;
	assert(br.readBytesNoCopy(1) == [2]);
	br.curBit = 1;
	assert(br.readBytesNoCopy(3) == [2,3,4]);
	br.curBit = 1;
	assert(br.readBytesNoCopy(4) is null);
}

unittest
{
	SwfBitReader br;
	{
		ubyte[3] bs = [2, 'h', 'i'];
		br = SwfBitReader(bs);
		assert(br.readASConstantString() == "hi");
		assert(!br.overflow);
	}
	{
		ubyte[2] bs = [2, 'h'];
		br = SwfBitReader(bs);
		assert(br.readASConstantString() is null);
		assert(br.overflow);
	}
}

unittest
{
	static immutable ubyte[] data = ['h', 'i', 0, 0, 'w', 'o', 'r', 'l', 'd', 0, 0];
	SwfBitReader br;
	br = SwfBitReader(data);
	assert(br.readNullTerminatedUtf8() == "hi"); assert(br.curBit == 24);
	{ auto t = br.readNullTerminatedUtf8(); assert(t == ""); assert(t !is null); }
	assert(br.readNullTerminatedUtf8() == "world");
	{ auto t = br.readNullTerminatedUtf8(); assert(t == ""); assert(t !is null); }
	assert(br.curBit == br.totalBits);
}

unittest
{
	static immutable ubyte[] data = ['a', 'b', 0];
	auto br = SwfBitReader(data);
	br.curBit = 1;
	assert(br.readNullTerminatedUtf8() == "b");
	br.curBit = 2;
	assert(br.readNullTerminatedUtf8() == "b");
	br.curBit = 15;
	assert(br.readNullTerminatedUtf8() == "");
	assert(!br.overflow);
	assert(br.curBit == 24);
}

unittest
{
	ubyte[2] bs = [1, 2];
	auto br = SwfBitReader(bs);
	assert(br.remaining == [1, 2]);
	br.readUB(1);
	assert(br.remaining == [2]);
}

unittest
{
	ubyte[4] bs;
	SwfBitReader br;
	br = SwfBitReader(bs); br.skipBytes(1); assert(br.curBit == 8);
	br = SwfBitReader(bs); br.skipBytes(2); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.skipBytes(4); assert(!br.overflow);
	br = SwfBitReader(bs); br.skipBytes(5); assert(br.overflow);
	br = SwfBitReader(bs); br.readUB(1); br.skipBytes(1); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.readUB(1); br.skipBytes(2); assert(br.curBit == 24);
	br = SwfBitReader(bs); br.readUB(1); br.skipBytes(4); assert(br.overflow);
	br = SwfBitReader(bs); br.readUB(1); br.skipBytes(5); assert(br.overflow);
	// ---
	br = SwfBitReader(bs); br.readUB(1); br.skipBytes(1); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.readUB(2); br.skipBytes(1); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.readUB(3); br.skipBytes(1); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.readUB(4); br.skipBytes(1); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.readUB(5); br.skipBytes(1); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.readUB(6); br.skipBytes(1); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.readUB(7); br.skipBytes(1); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.readUB(8); br.skipBytes(1); assert(br.curBit == 16);
	br = SwfBitReader(bs); br.readUB(9); br.skipBytes(1); assert(br.curBit == 24);
}

unittest
{
	SwfBitReader br;

	assert(!br.overflow);
	br = SwfBitReader([]);
	assert(br.readU30() == 0);
	assert(br.overflow);

	// 5 valid lengths
	assert(SwfBitReader([0b0_1100110]).readU30() == 0b1100110);
	assert(SwfBitReader([0b1_1100110, 0b0_0011001]).readU30() == 0b0011001_1100110);
	assert(SwfBitReader([0b1_1100110, 0b1_0011001, 0b0_1010111]).readU30() == 0b1010111_0011001_1100110);
	assert(SwfBitReader([0b1_1100110, 0b1_0011001, 0b1_1010111, 0b0_1000100]).readU30() == 0b1000100_1010111_0011001_1100110);
	assert(SwfBitReader([0b1_1100110, 0b1_0011001, 0b1_1010111, 0b1_1000100, 0b0_0000011]).readU30() == 0b11_1000100_1010111_0011001_1100110);

	// last one with overflow/not
	assert(SwfBitReader([0b1_1100110, 0b1_0011001, 0b1_1010111, 0b1_1000100, 0b0_0000000]).readU30() == 0b00_1000100_1010111_0011001_1100110);
	assert(SwfBitReader([0b1_1100110, 0b1_0011001, 0b1_1010111, 0b1_1000100, 0b0_0000010]).readU30() == 0b10_1000100_1010111_0011001_1100110);
	//assert(SwfBitReader([0b1_1100110, 0b1_0011001, 0b1_1010111, 0b1_1000100, 0b0_0000111]).readU30() == 0);
	//assert(SwfBitReader([0b1_1100110, 0b1_0011001, 0b1_1010111, 0b1_1000100, 0b1_0000011]).readU30() == 0);
	//assert(SwfBitReader([0b1_1100110, 0b1_0011001, 0b1_1010111, 0b1_1000100, 0b1_0000011, 0]).readU30() == 0);

	// overflow, size limit
	assert(SwfBitReader([0b1_1111111]).readU30() == 0);
	assert(SwfBitReader([0b1_1111111, 0b1_1111111]).readU30() == 0);
	assert(SwfBitReader([0b1_1111111, 0b1_1111111, 0b1_1111111]).readU30() == 0);
	assert(SwfBitReader([0b1_1111111, 0b1_1111111, 0b1_1111111, 0b1_1111111]).readU30() == 0);
	// allowed
	assert(SwfBitReader([0b1_1111111, 0b1_1111111, 0b1_1111111, 0b1_1111111, 0b1_1111111]).readU30() == -1);

	br = SwfBitReader([0b01111111]);
	assert(br.readU30() == 0b01111111);
	assert(br.curBit == 8);

	br = SwfBitReader([0b1_1000100, 0b0_0111010]); // 1 2
	assert(br.readU30() == 0b0111010_1000100); // 2 1
	assert(br.curBit == 16);

	br = SwfBitReader([0b1_1111111]);
	assert(br.readU30() == 0);
	assert(br.overflow);

	br = SwfBitReader([
		0b1_1000000, // 7
		0b1_0100000, // 14
		0b1_0010000, // 21
		0b1_0001000, // 28
		0b0_0000011, // 28+2=30
	]);
	assert(br.readU30() == 0b11_0001000_0010000_0100000_1000000);

	foreach (lastbyte; cast(ubyte[])[
		// good
		0b0_0000000,
		0b0_0000001,
		0b0_0000010,
		0b0_0000011,
		0b0_0000111,
		0b0_0001011,
		0b0_0001111,
		// bad - EDIT: these are allowed now
		0b0_0010000,
		0b0_0010011,
		0b0_0100011,
		0b0_1000011,
		0b1_0000011,
		0b1_1111111,
	])
	{
		br = SwfBitReader([
			0b1_1000000, // 7
			0b1_0100000, // 14
			0b1_0010000, // 21
			0b1_0001000, // 28
			lastbyte,
		]);
		assert(br.readU30() != 0);
		assert(!br.overflow);
	}
}

unittest // just to illustrate the byte order
{
	{
		auto br = SwfBitReader([0x01, 0x02, 0x03, 0x04, 0x05]);
		assert(br.readUI(8) == 0x01);
	}
	{
		auto br = SwfBitReader([0x01, 0x02, 0x03, 0x04, 0x05]);
		assert(br.readUI(16) == 0x0201);
	}
	{
		auto br = SwfBitReader([0x01, 0x02, 0x03, 0x04, 0x05]);
		assert(br.readUI(32) == 0x04030201);
	}
}
