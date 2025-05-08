module swfbiganal.swf.strings;

import swfbiganal.cdef.xxhash;

/**
 * A map thing to remember strings that have been encountered by their hash.
 */
struct SwfStrings
{
	/** context the string was seen in */
	enum StringType : ushort
	{
		as2,
		as3,
		text,
		text2,
		export_,
		object,
		fontName,
		fontCopyright,
		frameLabel,
	}

	alias StringTypeBits = ushort;
	static assert((1<<StringType.max) <= StringTypeBits.max);

	StringTypeBits[XXH64_hash_t] strings;

	/**
	 * Add a new sighting of a string. Returns true if the string hadn't been
	 * seen before (in any context), false otherwise.
	 */
	bool addNew(scope const(char)[] str, StringType type)
	{
		pragma(inline, false); // big, many call sites
		bool added;

		// old gdc lacks named aruments
		strings.update(
			/*key:*/ XXH3_64bits(cast(ubyte*)str.ptr, str.length),
			/*create:*/ () {
				added = true;
				return cast(StringTypeBits)(1<<type);
			},
			/*update:*/ (ref StringTypeBits val) {
				if ((val & (1<<type)) == 0)
				{
					val |= (1<<type);
					added = true;
				}
			},
		);

		return added;
	}
}
