module swfbiganal.swftypes.swfheader;

import swfbiganal.globals;

struct SwfHeader
{
	ubyte[3] signature;

	/** valid 1-255 */
	ubyte swfVersion;

	/**
	 * Size of the uncompressed SWF header + movie header + tag stream.
	 * 
	 * Flash Player also uses this as a size limit for reading the file.
	 */
	uint fileSize;

	bool isValid() const
	{
		return !validate;
	}

	const(char)* validate() const
	{
		if (signature[1..$] != "WS")
			return "wrong signature";

		switch (signature[0])
		{
			case 'C':
			case 'F':
			case 'Z':
				break;
			default:
				return "wrong signature or unknown compression method";
		}

		// flash will say "Movie not loaded"
		if (swfVersion == 0)
			return "invalid version";

		// flash has an arbitrary limit for the minimum size of a valid swf
		// note that this limit depends on the size in bytes of the display rect
		// rect size 1-3 -> file size 21
		// rect size 3+n -> file size 21+n (up to rect=17 with file=35)
		enum minSize = 21;
		if (fileSize < minSize)
			return "filesize too low";

		// flash will say "Movie not loaded"
		if (fileSize > 0x7fff_ffee)
			return "filesize too high";

		return null;
	}

	bool isCompressed() const
	{
		return (
			(signature[0] == 'C' || signature[0] == 'Z') &&
			signature[1..$] == "WS"
		);
	}

	bool isZlibCompressed() const
	{
		return signature == "CWS";
	}

	bool isLzmaCompressed() const
	{
		return signature == "ZWS";
	}
}
static assert(SwfHeader.sizeof == 8);
