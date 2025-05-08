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
		return frameRate[0]/256.0 + cast(byte)frameRate[1];
	}
}

unittest
{
	SwfMovieHeader mh;

	/*
	 * the frame rate field is documented in a very confusing way so i just
	 * implemented it like jpexs decompiler seems to do
	 * 
	 * https://www.m2osw.com/swf_tag_file_header
	 * 
	 * >The f_frame_rate is a fixed value of 8.8 bits. It represents the number
	 *  of frames per second the movie should be played at. Since version 8 of
	 *  SWF, it is defined as an unsigned short fixed point value instead of an
	 *  unsigned short. The lower 8 bits should always be zero (see comment
	 *  below.) This value should never be set to zero in older versions. Newer
	 *  versions use the value zero as "run at full speed" (which probably means
	 *  run synchronized to the video screen Vertical BLank or VBL.)
	 */

	mh.frameRate = [0x00, 0x00]; assert(mh.frameRateFps == 0.0);
	mh.frameRate = [0x00, 0x40]; assert(mh.frameRateFps == 64.0);
	mh.frameRate = [0x00, 0x80]; assert(mh.frameRateFps == -128.0);
	mh.frameRate = [0x40, 0x00]; assert(mh.frameRateFps == 0.25);
	mh.frameRate = [0x40, 0x40]; assert(mh.frameRateFps == 64.25);
	mh.frameRate = [0x40, 0x80]; assert(mh.frameRateFps == -127.75);
	mh.frameRate = [0x80, 0x00]; assert(mh.frameRateFps == 0.5);
	mh.frameRate = [0x80, 0x40]; assert(mh.frameRateFps == 64.5);
	mh.frameRate = [0x80, 0x80]; assert(mh.frameRateFps == -127.5);
}
