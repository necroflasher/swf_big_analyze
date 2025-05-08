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

	static void skip(ref SwfBitReader br)
	{
		// the top 5 bits are the bit size, the rest are part of the rect
		uint size = (br.read!ubyte >> 3);
		// multiply by 4 for each rect component
		// subtract 3 bits that were already read in the first byte
		// convert to bytes and round up: add 7 and divide by 8
		br.skipBytes( ((size*4-3) + 7) >> 3 );
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
		SwfRect(br);
		assert(!br.overflow);
		assert(br.curBit == totalBits);

		br = SwfBitReader(bs[0..totalBytes]);
		SwfRect.skip(br);
		assert(!br.overflow);
		assert(br.curBit == totalBits);
	}
}
