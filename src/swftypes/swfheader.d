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

		// smallest valid swf with nothing it in (swf header + movie header)
		// flash seems to require more but i'm not sure how it works
		enum minSize = SwfHeader.sizeof+1+2+2;
		if (fileSize < minSize)
			return "filesize too low";

		// flash will say "Movie not loaded"
		if (fileSize >= 0x8000_0000)
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
