module swfbiganal.swftypes.swfrgba;

import swfbiganal.swfbitreader;

struct SwfRgba
{
	ubyte r;
	ubyte g;
	ubyte b;
	ubyte a;

	this(ref SwfBitReader br)
	{
		r = cast(ubyte)br.read!ubyte;
		g = cast(ubyte)br.read!ubyte;
		b = cast(ubyte)br.read!ubyte;
		a = cast(ubyte)br.read!ubyte;
	}

	static void skip(ref SwfBitReader br)
	{
		br.skipBytes(4);
	}

	static void skip(ref SwfByteReader br)
	{
		br.skipBytes(4);
	}
}
