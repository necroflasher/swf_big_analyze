module swfbiganal.swftypes.swfanyfilter;

import swfbiganal.swfbitreader;
import swfbiganal.swftypes.swftag;

// https://www.m2osw.com/swf_struct_any_filter
struct SwfAnyFilter
{
	enum Type
	{
		DropShadow    =  0,
		Blur          =  1,
		Glow          =  2,
		Bevel         =  3,
		GradientGlow  =  4,
		Convolution   =  5,
		ColorMatrix   =  6,
		GradientBevel =  7,
	}

	// popularity ranking (~/flash/**/*.swf)
	//  29342 - @@@ 1 - Blur
	//  19885 - @@@ 2 - Glow
	//   3791 - @@@ 6 - ColorMatrix
	//   2237 - @@@ 0 - DropShadow
	//    280 - @@@ 7 - GradientBevel
	//    170 - @@@ 4 - GradientGlow
	//     68 - @@@ 3 - Bevel
	//      0 - @@@ 5 - Convolution

	static void skip(ref SwfBitReader br, ref SwfTag tag)
	{
		uint type = br.read!ubyte;

		uint bits;
		if (type == Type.Blur)
		{
			bits = 72;
		}
		else if (type == Type.Glow)
		{
			bits = 120;
		}
		else if (type == Type.ColorMatrix)
		{
			bits = 640;
		}
		else if (type == Type.DropShadow)
		{
			bits = 184;
		}
		else if (type == Type.Bevel)
		{
			bits = 216;
		}
		else if (
			type == Type.GradientBevel ||
			type == Type.GradientGlow)
		{
			uint count = br.read!ubyte;
			bits = (152 + 40*count);
		}
		else if (type == Type.Convolution)
		{
			uint columns = br.read!ubyte;
			uint rows    = br.read!ubyte;
			bits = (96 + 32*(columns*rows));
		}

		if (bits)
		{
			br.skipBits(bits);
		}
		else
		{
			tag.print("unknown filter type %u", type);
		}
	}
}
