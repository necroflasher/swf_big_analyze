module swfbiganal.util.urlencode;

import swfbiganal.util.appender;
import swfbiganal.util.utf8;

void urlEncodeMin(
	const(char)[] buf,
	scope void delegate(scope const(char)[]) cb)
{
	ScopedAppender!(char[]) ap;
	cb(urlEncodeMin(buf, ap));
}

void urlEncodeMin(
	const(ubyte)[] buf,
	scope void delegate(scope const(char)[]) cb)
{
	urlEncodeMin(cast(char[])buf, cb);
}

// -----------------------------------------------------------------------------

private:

/**
 * minimally url-encode a string
 * 
 * goals:
 * - encode spaces and control characters
 * - don't output invalid utf-8 (encode it)
 * - be able to urldecode it into the exact original
 * 
 * return value: either the original string (if it wasn't encoded), or the
 *  contents of the appender (if it was encoded and appended there)
 */
const(char)[] urlEncodeMin(
	const(char)[] str,
	ref ScopedAppender!(char[]) ap)
{
	pragma(inline, false); // big
	//
	// do a loop first to check if the string needs any percent-encoding at all
	// (many don't, so there's no need to make a copy of the string in that case)
	//
	int utfvalid = 0; // -1=no 1=yes 0=maybe
	size_t idx; // index of char that triggered percent-encoding [ones before this don't need it]
	foreach (i, c; str)
	{
		if (c <= ' ' || c == '%' || c == 0x7f)
		{
			idx = i;
			goto needsEncode;
		}
		if (c >= 0x80 && !utfvalid)
		{
			// barf vomit
			// if the string has invalid utf-8, just percent-encode all utf-8 in it
			utfvalid = 1;
			if (!IsUTF8(cast(ubyte[])str[i..$]))
			{
				utfvalid = -1;
				idx = i;
				goto needsEncode;
			}
		}
	}
	return str;

needsEncode:
	//
	// if we got here, it means the string is going to be percent-encoded
	//
	ap.reserve(str.length+2); // will encode at least one char
	ap ~= str[0..idx];
	foreach (c; str[idx..$])
	{
		if (c <= ' ' || c == '%' || c == 0x7f || (c >= 0x80 && utfvalid == -1))
		// char that needs percent encoding (control chars, percent sign, utf-8 in a malformed string)
		{
apEncode:
			static immutable hexdigits = "0123456789abcdef";
			char[3] t = [
				'%',
				hexdigits[c >> 4],
				hexdigits[c & 0b1111],
			];
			ap ~= t;
		}
		else if (c < 0x80 || utfvalid == 1)
		// char that's safe by itself (safe ascii OR string with valid utf-8)
		{
apPlain:
			ap ~= c;
		}
		else
		// need to check utf-8 validity before we can proceed further
		{
			version(unittest) assert(!utfvalid);

			utfvalid = 1;
			if (!IsUTF8(cast(ubyte[])str))
			{
				utfvalid = -1;
				goto apEncode;
			}
			goto apPlain;
		}
	}
	// unittest: these strings don't need their utf validity checked
	version(unittest) if (str == "asd") assert(!utfvalid);
	version(unittest) if (str == "a d") assert(!utfvalid);
	return ap[];
}

unittest
{
	static char[] urlEncodeMin(const(char)[] str)
	{
		char[] rv;
		.urlEncodeMin(str, (scope s)
		{
			rv = s.dup;
		});
		return rv;
	}
	assert(urlEncodeMin("asd") == "asd");
	assert(urlEncodeMin("a d") == "a%20d");
	assert(urlEncodeMin("a\xffd") == "a%ffd");
	assert(urlEncodeMin("aäd") == "aäd");
	assert(urlEncodeMin("a äd") == "a%20äd");
	assert(urlEncodeMin("a äd\xff") == "a%20%c3%a4d%ff");
	assert(urlEncodeMin("aä d") == "aä%20d");
	assert(urlEncodeMin("aä d\xff") == "a%c3%a4%20d%ff");
	// ä is encoded if it's before invalid utf-8
	assert(urlEncodeMin("aäd") == "aäd");
	assert(urlEncodeMin("aäd\xff") == "a%c3%a4d%ff");
}
