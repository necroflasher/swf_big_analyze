module swfbiganal.swftypes.swfrgb;

import swfbiganal.swfbitreader;

struct SwfRgb
{
	ubyte r;
	ubyte g;
	ubyte b;

	this(ref SwfBitReader br)
	{
		r = cast(ubyte)br.read!ubyte;
		g = cast(ubyte)br.read!ubyte;
		b = cast(ubyte)br.read!ubyte;
	}

	static void skip(ref SwfBitReader br)
	{
		br.skipBytes(3);
	}

	static void skip(ref SwfByteReader br)
	{
		br.skipBytes(3);
	}
}
