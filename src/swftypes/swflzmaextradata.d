module swfbiganal.swftypes.swflzmaextradata;

/// extra values after the SwfHeader in lzma-compressed .swf
public struct SwfLzmaExtraData
{
align(1):;
	// size of the lzma data that comes after this header
	// normally the rest of the file, or (compressedFileSize - (SwfHeader.sizeof+SwfLzmaExtraData.sizeof))
	uint lzmaBodySize;

	// parts of the lzma_alone header
	// https://git.tukaani.org/?p=xz.git;a=blob;f=doc/lzma-file-format.txt;h=4865defd5cf22716d68dbc4621897e6186afffe5;hb=HEAD
	ubyte properties;
	uint  dictionarySize;

	ubyte[13] toLzmaHeader() const
	{
		union U
		{
			LzmaHeader               l;
			ubyte[LzmaHeader.sizeof] b;
		}
		return U(LzmaHeader(properties, dictionarySize, -1)).b;
	}
}
static assert(SwfLzmaExtraData.sizeof == 4+1+4);

private struct LzmaHeader
{
align(1):;
	ubyte properties;
	uint  dictionarySize;
	ulong uncompressedSize; // -1 to auto-detect
}
static assert(LzmaHeader.sizeof == 1+4+8);
