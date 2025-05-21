module swfbiganal.swf.errors;

// swf file can't be opened for reasons ("movie not loaded")
// makes sense to quit reading on these
enum SwfSoftError : uint
{
	badHeader,      // not FWS/CWS/ZWS with version >= 1
	headerSizeLow,  // too low size field
	headerSizeHigh, // too high size field

	movieTooShort,  // didn't read enough movie data
};

// movie contains corrupt data and flash player closes in protest
enum SwfHardError : uint
{
	// end position (offset+length in the file) of a tag exceeds int.max
	// guess it's treated as signed somewhere
	tagEndOverflow,

	// FileAttributes tag has the AS3 bit set in SWF 1-8
	as3InOldFlash,
};

// NOTE: main.d prints these, keep them as url-safe ascii (no spaces)

const(char)* toString(SwfSoftError se)
{
	with (SwfSoftError)
	final switch (se)
	{
		case badHeader:      return "bad-header";
		case headerSizeLow:  return "header-size-low";
		case headerSizeHigh: return "header-size-high";
		case movieTooShort:  return "movie-too-short";
	}
}

const(char)* toString(SwfHardError se)
{
	with (SwfHardError)
	final switch (se)
	{
		case tagEndOverflow: return "tag-end-overflow";
		case as3InOldFlash:  return "fileattributes-as3-in-old-flash";
	}
}
