module swfbiganal.swftypes.swfrect;

import swfbiganal.util.compiler;
import swfbiganal.swfbitreader;

struct SwfRect
{
	int xmin;
	int xmax;
	int ymin;
	int ymax;
	uint bits;

	this(ref SwfBitReader br)
	{
		bits = (br.read!ubyte >> 3);
		if (expect(!br.overflow, true))
		{
			br.curBit -= 3;
			xmin = br.readSB(bits);
			xmax = br.readSB(bits);
			ymin = br.readSB(bits);
			ymax = br.readSB(bits);
			br.byteAlign();
		}
	}

	version (unittest)
	this(int xmin_, int xmax_)
	{
		xmin = xmin_;
		xmax = xmax_;
	}

	static void skip(ref SwfBitReader br)
	{
		// the top 5 bits are the bit size, the rest are part of the rect
		uint size = (br.read!ubyte >> 3);
		// multiply by 4 for each rect component
		// subtract 3 bits that were already read in the first byte
		// convert to bytes and round up: add 7 and divide by 8
		br.skipBytes( ((size*4-3) + 7) >> 3 );
	}

	int widthPx()
	{
		return (xmax - xmin) / 20;
	}

	int heightPx()
	{
		return (ymax - ymin) / 20;
	}

	size_t lengthBytes()
	{
		return (5 + 4*bits + 7) / 8;
	}
}

unittest
{
	SwfBitReader br;

	// 0 to 31 bits
	foreach (bits; 0..0b11111+1)
	{
		ubyte[17] bs;
		bs[0] = cast(ubyte)(bits << 3);

		uint totalBits = 5 + 4*bits;
		totalBits = (totalBits + 7) & ~0b111; // byte-align

		uint totalBytes = totalBits/8;

		br = SwfBitReader(bs[0..totalBytes]);
		auto sr = SwfRect(br);
		assert(!br.overflow);
		assert(br.curBit == totalBits);
		assert(sr.lengthBytes == totalBytes);

		br = SwfBitReader(bs[0..totalBytes]);
		SwfRect.skip(br);
		assert(!br.overflow);
		assert(br.curBit == totalBits);
	}
}

unittest
{
	// based on testing (display rect + AS2 Stage.width)
	// it does give negative values, but they obviously get clamped to zero for
	//  the program window

	// min=0 max=0-19 -> 0
	// min=0 max=20-39 -> 1
	// min=0 max=40-59 -> 2
	assert(SwfRect(0, 0).widthPx == 0);
	assert(SwfRect(0, 19).widthPx == 0);
	assert(SwfRect(0, 20).widthPx == 1);
	assert(SwfRect(0, 39).widthPx == 1);
	assert(SwfRect(0, 40).widthPx == 2);
	assert(SwfRect(0, 59).widthPx == 2);

	// min=1 max=0-20 -> 0
	// min=1 max=21-40 -> 2
	assert(SwfRect(1, 0).widthPx == 0);
	assert(SwfRect(1, 20).widthPx == 0);
	assert(SwfRect(1, 21).widthPx == 1);
	assert(SwfRect(1, 40).widthPx == 1);
	assert(SwfRect(1, 41).widthPx == 2);

	// silly!
	// min=-1 max=0-18 -> 0
	// min=-1 max=19-38 -> 1
	assert(SwfRect(-1, 0).widthPx == 0);
	assert(SwfRect(-1, 18).widthPx == 0);
	assert(SwfRect(-1, 19).widthPx == 1);
	assert(SwfRect(-1, 38).widthPx == 1);
	assert(SwfRect(-1, 39).widthPx == 2);

	// silly!
	// min=0 max=-(0-19) -> 0
	// min=0 max=-(20-39) -> -1
	assert(SwfRect(0, 0).widthPx == 0);
	assert(SwfRect(0, -19).widthPx == 0);
	assert(SwfRect(0, -20).widthPx == -1);
	assert(SwfRect(0, -39).widthPx == -1);
	assert(SwfRect(0, -40).widthPx == -2);
}
