module swfbiganal.swftypes.swfshape;

import swfbiganal.swfbitreader;
import swfbiganal.swftypes.swfgradient;
import swfbiganal.swftypes.swfmatrix;
import swfbiganal.swftypes.swftag;
import swfbiganal.util.compiler;

// https://www.m2osw.com/swf_struct_shape
//  https://www.m2osw.com/swf_struct_styles_count
//  https://www.m2osw.com/swf_struct_shape_record
// doc: "Fonts use this declaration. It does not include any style (fill or
//  line) definitions. The drawing will use fill 0 when the inside of the shape
//  should not be drawn and 1 when it is to be filled. The line style should
//  not be defined."
struct SwfShape
{
	static void skip(ref SwfBitReader br, ref SwfTag tag)
	{
		uint bitCounts = br.read!ubyte;

		uint numFillBits = bitCounts >> 4;
		uint numLineBits = bitCounts & 0b1111;

		for (;;)
		{
			uint recordHead = br.readUB!6;

			enum IsEdgeRecord = 0b_1_0_0000;

			if (expect((recordHead & IsEdgeRecord) != 0, true))
			{
				enum EdgeType1 = 0b_0_1_0000;
				enum CoordSize = 0b_0_0_1111;

				uint coordSize = (recordHead & CoordSize);
				uint coordRealSize = coordSize+2;

				uint bits;

				if (recordHead & EdgeType1)
				{
					if (br.readUB!1)
					{
						bits = 2*coordRealSize;
					}
					else
					{
						bits = 1+coordRealSize;
					}
				}
				else
				{
					bits = 4*coordRealSize;
				}

				br.skipBits(bits);
			}
			else if (recordHead != 0)
			{
				enum HasNewStyles  = 0b_0_1_0000;
				enum HasLineStyle  = 0b_0_0_1000;
				enum HasFillStyle1 = 0b_0_0_0100;
				enum HasFillStyle0 = 0b_0_0_0010;
				enum HasMoveTo     = 0b_0_0_0001;

				if (expect((recordHead & HasNewStyles) != 0, false))
				{
					// SwfShape (used for fonts) isn't meant to have this
					tag.print("font shape has HasNewStyles bit set");
					br.setOverflow();
					return;
				}

				uint bits;
				if (expect((recordHead & HasMoveTo) != 0, true))
				{
					bits += 2*br.readUB!5;
				}
				if (recordHead & HasFillStyle0) bits += numFillBits;
				if (recordHead & HasFillStyle1) bits += numFillBits;
				if (recordHead & HasLineStyle) bits += numLineBits;
				br.skipBits(bits);
			}
			else
			{
				break;
			}
		}
	}
}
