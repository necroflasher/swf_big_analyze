/*
 * from: https://bjoern.hoehrmann.de/utf-8/decoder/dfa/ (Rich Felker version)
 * 
 * Copyright (c) 2008-2010 Bjoern Hoehrmann <bjoern@hoehrmann.de>
 * See http://bjoern.hoehrmann.de/utf-8/decoder/dfa/ for details.
 */
module swfbiganal.util.utf8;

private enum UTF8_ACCEPT = 0;
private enum UTF8_REJECT = 12;

// compare the result of IsUTF8 with the D standard library's equivalent
//~ debug = compareWithPhobos;

bool IsUTF8(scope const(ubyte)[] str)
{
	pragma(inline, false);
	uint codepoint;
	uint state;

	// note: state can be a value other than the two enums when it's in the
	// middle of a multi-byte character
	foreach (b; str)
	{
		if (decode(&state, &codepoint, b) == UTF8_REJECT)
			break;
	}

	debug(compareWithPhobos)
		compareValidWithPhobos(str, (state == UTF8_ACCEPT));

	return (state == UTF8_ACCEPT);
}

debug(compareWithPhobos)
private void compareValidWithPhobos(const(ubyte)[] str, bool thisLibValid)
{
	static import std.utf;
	import core.stdc.stdio : printf;

	bool phobosValid = true;
	try
		std.utf.validate(cast(char[])str);
	catch (std.utf.UTFException e)
		phobosValid = false;

	if (phobosValid != thisLibValid)
	{
		printf("string validity differs: phobos=%u this=%u - %.*s\n",
			phobosValid,
			thisLibValid,
			cast(int)str.length, str.ptr);
	}
}

private uint decode(uint* state, uint* codep, ubyte byte_)
{
	pragma(inline, true);
	uint type = utf8d[byte_];

	*codep = (*state != UTF8_ACCEPT)
		? (byte_ & 0x3f) | (*codep << 6)
		: (0xff >> type) & (byte_);

	*state = utf8d[256 + *state + type];
	return *state;
}

private static immutable ubyte[364] utf8d = [
/++/ // The first part of the table maps bytes to character classes that
/++/ // reduce the size of the transition table and create bitmasks.
/++/  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
/++/  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
/++/  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
/++/  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
/++/  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,  9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
/++/  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
/++/  8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
/++/ 10,3,3,3,3,3,3,3,3,3,3,3,3,4,3,3, 11,6,6,6,5,8,8,8,8,8,8,8,8,8,8,8,
/++/ 
/++/ // The second part is a transition table that maps a combination
/++/ // of a state of the automaton and a character class to a state.
/++/  0,12,24,36,60,96,84,12,12,12,48,72, 12,12,12,12,12,12,12,12,12,12,12,12,
/++/ 12, 0,12,12,12,12,12, 0,12, 0,12,12, 12,24,12,12,12,12,12,24,12,24,12,12,
/++/ 12,12,12,12,12,12,12,24,12,12,12,12, 12,24,12,12,12,12,12,12,12,24,12,12,
/++/ 12,12,12,12,12,12,12,36,12,36,12,12, 12,36,12,12,12,12,12,36,12,36,12,12,
/++/ 12,36,12,12,12,12,12,12,12,12,12,12,
];

unittest
{
	assert(IsUTF8(cast(ubyte[])""));
	assert(IsUTF8(cast(ubyte[])"hello"));
	assert(IsUTF8(cast(ubyte[])"👶")); // non-BMP
	assert(!IsUTF8(cast(ubyte[])"👶"[0..$-1])); // incomplete
	assert(!IsUTF8(cast(ubyte[])"hello\xff"));
	assert(!IsUTF8(cast(ubyte[])"hello\xff world"));
	assert(!IsUTF8(cast(ubyte[])"\xF0\x82\x82\xAC")); // overlong € (wikipedia)
	assert(!IsUTF8(cast(ubyte[])"\xED\xA0\x80")); // surrogate (https://www.compart.com/en/unicode/U+D800)
	assert(IsUTF8(cast(ubyte[])"hello\0world")); // allowed, but urlencode.d will escape this

	// fails, but GNU grep doesn't consider this invalid UTF-8 so maybe it's fine
	//~ assert(!IsUTF8(cast(ubyte[])"\xef\xbf\xbf")); // not a valid character (https://www.fileformat.info/info/unicode/char/ffff/index.htm)
}
