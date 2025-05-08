module swfbiganal.swftypes.swfgradient;

import swfbiganal.swfbitreader;
import swfbiganal.swftypes.swftag;

// https://www.m2osw.com/swf_struct_gradient
struct SwfGradient
{
	static void skip(ref SwfBitReader br, ref SwfTag tag, uint fillStyleType)
	{
		uint flags = br.read!ubyte;
		uint recordCount = (flags & 0b1111);

		uint gradientBits;

		// https://www.m2osw.com/swf_struct_gradient_record
		uint recordBits;
		if (tag.code == SwfTagCode.DefineMorphShape || tag.code == SwfTagCode.DefineMorphShape2)
		{
			recordBits = 80;
		}
		else if (tag.code == SwfTagCode.DefineShape3 || tag.code == SwfTagCode.DefineShape4)
		{
			recordBits = 40;
		}
		else
		{
			recordBits = 32;
		}
		gradientBits += recordCount*recordBits;

		if (fillStyleType == 0x13)
		{
			gradientBits += 16;
		}

		br.skipBits(gradientBits);
	}
}
