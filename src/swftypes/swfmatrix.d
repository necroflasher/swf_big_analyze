module swfbiganal.swftypes.swfmatrix;

import swfbiganal.swfbitreader;

// https://web.archive.org/web/20160324025038/http://www.m2osw.com/swf_struct_matrix
struct SwfMatrix
{
	static void skip(ref SwfBitReader br)
	{
		br.byteAlign();
		if (br.readUB!1)
		{
			br.skipBits(2*br.readUB!5);
		}
		if (br.readUB!1)
		{
			br.skipBits(2*br.readUB!5);
		}
		br.skipBits(2*br.readUB!5);
		br.byteAlign();
	}
}
