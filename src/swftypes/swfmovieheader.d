module swfbiganal.swftypes.swfmovieheader;

import swfbiganal.swfbitreader;
import swfbiganal.swftypes.swfrect;

struct SwfMovieHeader
{
	SwfRect  display;
	ubyte[2] frameRate;
	uint     frameCount;

	this(ref SwfBitReader br)
	{
		display      = SwfRect(br);
		frameRate[0] = cast(ubyte)br.read!ubyte;
		frameRate[1] = cast(ubyte)br.read!ubyte;
		frameCount   = br.read!ushort;
	}

	double frameRateFps() const
	{
		return frameRate[0]/256.0 + frameRate[1];
	}
}

unittest
{
	SwfMovieHeader mh;

	// this matches the output of jpexs decompiler, except that the value can't
	// be negative

	// (flash player seems to have an upper limit of around 100 frames per
	// second, and that includes the "negative" range)

	mh.frameRate = [0x00, 0x00]; assert(mh.frameRateFps == 0.0);
	mh.frameRate = [0x00, 0x40]; assert(mh.frameRateFps == 64.0);
	mh.frameRate = [0x00, 0x80]; assert(mh.frameRateFps == 128.0);
	mh.frameRate = [0x40, 0x00]; assert(mh.frameRateFps == 0.25);
	mh.frameRate = [0x40, 0x40]; assert(mh.frameRateFps == 64.25);
	mh.frameRate = [0x40, 0x80]; assert(mh.frameRateFps == 128.25);
	mh.frameRate = [0x80, 0x00]; assert(mh.frameRateFps == 0.5);
	mh.frameRate = [0x80, 0x40]; assert(mh.frameRateFps == 64.5);
	mh.frameRate = [0x80, 0x80]; assert(mh.frameRateFps == 128.5);
}
