module swfbiganal.swftypes.swfcolortransform;

import swfbiganal.swfbitreader;
import swfbiganal.swftypes.swftag;

// https://web.archive.org/web/20160324020853/http://www.m2osw.com/swf_struct_color_transform
struct SwfColorTransform
{
	// NOTE: doc doesn't say it but PlaceObject3 has alpha too
	// http://127.1.1.1/dbtest.php?do=analyze&md5=3D02D62146D8581980EB4951EE4B7402
	// NOTE: DefineButton2 too
	// http://127.1.1.1/dbtest.php?do=analyze&md5=BC2DAB2F27D148A397DBE27A0D83FADE

	static void skipWithAlpha(ref SwfBitReader br, ref SwfTag tag)
	in (
		tag.code == SwfTagCode.PlaceObject2 ||  // 26
		tag.code == SwfTagCode.DefineButton2 || // 34
		tag.code == SwfTagCode.PlaceObject3)    // 70
	{
		uint flags = (br.read!ubyte >> 2);

		enum HasAdd    = 0b10_0000;
		enum HasMult   = 0b01_0000;
		enum ColorBits = 0b00_1111;

		// total bit size of all the colors
		uint bits = (
			!!(flags & HasAdd) +
			!!(flags & HasMult)
		) * (flags & ColorBits) * 4;

		// subtract 2 bits already read in the first byte
		// round up to bytes: add 7 and divide by 8
		br.skipBytes( ( (bits-2) + 7 ) / 8 );
	}
}

unittest
{
	SwfTag tag = {code: SwfTagCode.PlaceObject2};
	static immutable byteSizes = [
		1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9,
		1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9,
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
	];
	uint idx;
	foreach (hasAdd; 0..1+1)
	foreach (hasMult; 0..1+1)
	foreach (colorBits; 0..0b1111+1)
	{
		uint flags = hasAdd<<7 | hasMult<<6 | colorBits<<2;
		ubyte[16] bs = void;
		bs[0] = cast(ubyte)flags;
		auto br = SwfBitReader(bs);
		SwfColorTransform.skipWithAlpha(br, tag);
		assert(!br.overflow);
		br.byteAlign();
		assert(br.curBit/8 == byteSizes[idx++]);
	}
	assert(idx == byteSizes.length);
}
