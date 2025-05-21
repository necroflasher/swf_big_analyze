module swfbiganal.swftypes.swfheader;

import swfbiganal.swf.errors;
import swfbiganal.util.enumset;

struct SwfHeader
{
	ubyte[3] signature;
	ubyte    swfVersion;
	uint     fileSize;

	bool isValid() const
	{
		return !validate;
	}

	const(char)* validate(EnumSet!SwfSoftError* se = null) const
	{
		if (signature[1..$] != "WS")
		{
			if (se)
				se.add(SwfSoftError.badHeader);
			return "wrong signature";
		}

		switch (signature[0])
		{
			case 'C':
			case 'F':
			case 'Z':
				break;
			default:
				if (se)
					se.add(SwfSoftError.badHeader);
				return "wrong signature or unknown compression method";
		}

		// flash will say "Movie not loaded"
		if (swfVersion == 0)
		{
			if (se)
				se.add(SwfSoftError.badHeader);
			return "invalid version";
		}

		// flash has an arbitrary limit for the minimum size of a valid swf
		// note that this limit depends on the size in bytes of the display rect
		// rect size 1-3 -> file size 21
		// rect size 3+n -> file size 21+n (up to rect=17 with file=35)
		enum minSize = 21;
		if (fileSize < minSize)
		{
			if (se)
				se.add(SwfSoftError.headerSizeLow);
			return "filesize too low";
		}

		// flash will say "Movie not loaded"
		if (fileSize > 0x7fff_ffee)
		{
			if (se)
				se.add(SwfSoftError.headerSizeHigh);
			return "filesize too high";
		}

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
