module swfbiganal.util.explainbytes;

import swfbiganal.util.appender;
import swfbiganal.util.compiler;

@cold
void explainBytes(
	scope const(ubyte)[] data,
	size_t maxLen,
	scope void delegate(scope const(char)[]) cb)
{
	ScopedAppender!(char[]) ap;
	explainBytes(data, ap, maxLen);
	cb(ap[]);
}

@cold
void explainBytes(
	scope const(ubyte)[] data,
	scope void delegate(scope const(char)[]) cb)
{
	explainBytes(data, -1, cb);
}

// -----------------------------------------------------------------------------

private:

void explainBytes(scope const(ubyte)[] data, ref ScopedAppender!(char[]) ap, size_t maxLen = -1)
{
	pragma(inline, false); // big
	static immutable hexdigits = "0123456789abcdef";

	if (data.length > maxLen)
	{
		data = data[0..maxLen];
	}

	ap.reserve(data.length+2); // it'll be at least this big

	bool inPrintable;

	foreach (i, b; data)
	{
		if (b > ' ' && b < 0x7f)
		{
			if (!inPrintable)
			{
				if (i) ap ~= "-'";
				else   ap ~= '\'';
			}
			ap ~= cast(char)b;
		}
		else
		{
			if (i)
			{
				if (inPrintable) ap ~= "'-";
				else             ap ~= '-';
			}
			ap ~= [
				hexdigits[b >> 4],
				hexdigits[b & 0b1111],
			];
		}
		inPrintable = (b > ' ' && b < 0x7f);
	}

	if (inPrintable)
	{
		ap ~= '\'';
	}
}

version(unittest)
string explainBytes(scope const(ubyte)[] buf, size_t maxLen = -1)
{
	string rv;
	explainBytes(buf, maxLen, (scope s)
	{
		rv = s.idup;
	});
	return rv;
}

unittest
{
	import std.string : representation; // grep: unittest

	assert(explainBytes("asd".representation) == "'asd'");
	assert(explainBytes("SWF\x01\xaa\xab\xac\xad".representation) == "'SWF'-01-aa-ab-ac-ad");
	assert(explainBytes("a b c".representation) == "'a'-20-'b'-20-'c'");
	assert(explainBytes("heh".representation, 2) == "'he'");
	assert(explainBytes(" hi".representation) == "20-'hi'");
}
