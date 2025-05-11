module swfbiganal.swf.fontglyphs;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.bitop : byteswap;
import swfbiganal.cdef.iconv;
import swfbiganal.globals;
import swfbiganal.swftypes.swftag;
import swfbiganal.util.compiler;

alias ParsedFont = FontGlyphs;

/**
 * holds a valid utf-8 byte sequence (for glyphs that were decoded correctly)
 *  or a marker, set of flags and the original bytes of the glyph
 * 
 * for valid utf-8, the sequence is stored in `bytes`. its length can be
 *  obtained by `utf8_len(bytes[0])`. bytes beyond the length are uninitialized
 *  and should not be used
 * 
 * for invalid glyphs, the first byte will be 0xff, second byte is a FlagByte
 *  enum, and the remaining two bytes are the original bytes of the glyph
 *  before decoding. there can be 1 or 2 original glyphs, check the isWide
 *  member to see which it is
 */
private struct GlyphEntity
{
	union
	{
		ubyte[4] bytes;
		uint     u;
	}
	alias bytes this; // old syntax for old gdc

	bool isValid()
	{
		return (bytes[0] != 0xff);
	}

	char[] asText() return
	{
		assert(isValid);

		return cast(char[])bytes[0..utf8_len(bytes[0])];
	}

	ref ubyte flagByte() return
	{
		assert(!isValid);

		return bytes[1];
	}

	ubyte[] originalBytes(ref const(FontGlyphs) font) return
	{
		assert(!isValid);

		if (bytes[2] != 0)
			return bytes[2..4];
		else
			return bytes[3..4];
	}
}

/**
 * a flag stored for glyphs that weren't decoded correctly
 * 
 * currently this is used to remember if a "bad glyph" warning has been
 *  printed already
 */
private enum FlagByte : ubyte
{
	initial = 0,
	used    = 1<<0,
	warned  = 1<<1,
}

struct FontGlyphs
{
	static immutable char[3] replacementStr = [0xef, 0xbf, 0xbd];

	private GlyphEntity[] glyphs;

	private bool badGlyphsPendingWarning;
	private bool usesLegacyEncodings;
	private bool isWide;
	private const(char)* defaultCharset;

	ushort id;

	@disable this(this);

	~this()
	{
		free(glyphs.ptr);
		glyphs = null;
	}

	this(
		ushort               id,
		bool                 isWide,
		scope const(ubyte)[] mapBytes,
		uint                 swfVersion,
		const(char)*         defaultCharset)
	{
		pragma(inline, false); // big, two call sites

		this.id = id;
		this.isWide = isWide;
		this.usesLegacyEncodings = (swfVersion <= 5);
		this.defaultCharset = defaultCharset;

		const(char)* fontCoding = codingNameForGlyphDecode();

		size_t glyphSize = (isWide?2:1);
		size_t glyphCount = mapBytes.length/glyphSize;

		glyphs = (cast(GlyphEntity*)malloc(4*glyphCount))[0..glyphCount];

		if (!fontCoding)
		{
			assert(swfVersion >= 6 && !isWide); // checked earlier, just a reminder

			foreach (glyphIndex, b; mapBytes)
			{
				// these should be utf-8 (or similar) but can't be multi-byte
				// TODO: find a flash that has non-ascii chars here
				if (expect((b & 0x80) == 0, true))
				{
					glyphs[glyphIndex].u = cast(uint)b;
				}
				else
				{
					glyphs[glyphIndex].u = 0xff|b<<24;
				}
			}

			return;
		}

		iconv_t cd = iconv_open("UTF-8", fontCoding); // to, from

		foreach (glyphIdx, ref glyph; glyphs)
		{
			size_t i = glyphIdx*glyphSize;

			ubyte[2] buf = [
				isWide ? mapBytes[i+1] : 0,
				mapBytes[i],
			];

			const(void)* inPtr = &buf[0];
			size_t       inLength = 2;

			if (!isWide || (!buf[0] && swfVersion <= 5))
			{
				inPtr = &buf[1];
				inLength = 1;
			}

			void*  outPtr    = glyph.bytes.ptr;
			size_t outLength = 4;

			iconv(cd, &inPtr, &inLength, &outPtr, &outLength);

			if (
				expect(inLength == 0, true) &&
				expect(4-outLength == utf8_len(glyph[0]), true))
			{
				continue;
			}

			glyph.u = 0xff|(*cast(ushort*)buf.ptr)<<16;
		}

		iconv_close(cd);
	}

	size_t hasGlyphs() const
	{
		return (glyphs.length != 0);
	}

	/**
	 * get the UTF-8 text of a glyph
	 * 
	 * the return value is a single code point encoded as UTF-8
	 * 
	 * if the glyph doesn't exist, returns null
	 * if the glyph exists but couldn't be decoded, returns the replacement character
	 */
	const(char)[] glyphText(uint idx)
	{
		if (expect(idx >= glyphs.length, false))
		{
			return null;
		}

		GlyphEntity* glyph = &glyphs[idx];

		if (expect(!glyph.isValid, false))
		{
			glyph.flagByte |= FlagByte.used;
			badGlyphsPendingWarning |= ((glyph.flagByte & FlagByte.warned) == 0);
			return replacementStr;
		}

		return glyph.asText;
	}

	/**
	 * print warnings for all badly encoded glyphs that were used since the last
	 *  call to this function
	 */
	void checkGlyphs(ref const(SwfTag) tag)
	{
		if (expect(!badGlyphsPendingWarning, true))
		{
			return;
		}

		foreach (glyphIndex, ref g; glyphs)
		{
			if (g.isValid || (g.flagByte & (FlagByte.used|FlagByte.warned)) != FlagByte.used)
			{
				continue;
			}

			char[6] buf = void;

			const(ubyte)[] bytes = g.originalBytes(this);
			if (bytes.length == 1)
				sprintf(buf.ptr, "%02hhx", bytes[0]);
			else if (bytes.length == 2)
				sprintf(buf.ptr, "%02hhx-%02hhx", bytes[0], bytes[1]);
			else
				assert(0);

			tag.print("failed to decode glyph %zu of font %hu as %s: <%s>", glyphIndex, id, codingName, buf.ptr);

			g.flagByte |= FlagByte.warned;
		}

		badGlyphsPendingWarning = false;
	}

private:

	static void swapBytes(ubyte[] mapBytes)
	{
		// this is checked before constructing the FontGlyphs
		// ldc will insert a check here but this way is smaller
		if ((mapBytes.length & 1) != 0)
		{
			assert(0);
		}
		foreach (ref b; cast(ushort[])mapBytes)
		{
			b = b.byteswap;
		}
	}

	/**
	 * get the name of the encoding used for this font
	 */
	const(char)* codingName()
	{
		const(char)* fontCoding;
		if (!usesLegacyEncodings)
		{
			if (isWide)
				fontCoding = "UCS-2LE"; // utf-16
			else
				fontCoding = "UTF-8"; // utf-8
		}
		else
		{
			if (defaultCharset)
				fontCoding = defaultCharset; // system locale
			if (!fontCoding)
				fontCoding = "CP1252"; // reasonable fallback
		}
		return fontCoding;
	}

	/**
	 * get the coding name to decode the mapBytes from (if it needs decoding)
	 * 
	 * returns null if they do not need decoding
	 */
	const(char)* codingNameForGlyphDecode()
	{
		const(char)* fontCoding;
		if (!usesLegacyEncodings)
		{
			if (isWide)
				fontCoding = "UCS-2BE"; // utf-16
			else
				fontCoding = null; // utf-8
		}
		else
		{
			if (defaultCharset)
				fontCoding = defaultCharset; // system locale
			else
				fontCoding = "CP1252"; // reasonable fallback
		}
		return fontCoding;
	}
}

// -----------------------------------------------------------------------------

// https://codegolf.stackexchange.com/a/173577
// get the length of a utf-8 byte sequence from its first byte (assuming valid input)
private uint utf8_len(char src)
{
	return ( (src-160) >> (20-(src/16)) )+2;
}

unittest
{
	assert(utf8_len('a') == 1);
	assert(utf8_len(0x7f) == 1);
	assert(utf8_len(0xc0) == 2);
	assert(utf8_len(0xdf) == 2);
	assert(utf8_len(0xe0) == 3);
	assert(utf8_len(0xef) == 3);
	assert(utf8_len(0xf0) == 4);
	assert(utf8_len(0xfe) == 4);
	assert(utf8_len('\0') == 1);
	assert(utf8_len(0xff) == 4);
}

unittest
{
	ParsedFont fnt;
	const(char)* cs;

	// utf-16 surrogate
	cs = null;
	fnt = ParsedFont(0, true, [0x00, 0xd8], 6, cs); // little-endian 0xD800
	assert(!fnt.glyphs[0].isValid);
	assert(fnt.glyphs[0].originalBytes(fnt) == [0xd8, 0x00]);

	// bad "unspecified utf-8"
	cs = null;
	fnt = ParsedFont(0, false, [0xff], 6, cs);
	assert(!fnt.glyphs[0].isValid);
	assert(fnt.glyphs[0].originalBytes(fnt) == [0xff]);

	// bad SJIS multi-byte
	cs = "CP932"; // Shift_JIS
	fnt = ParsedFont(0, true, [0xff, 0x81], 5, cs); // little-endian 81 ff
	assert(!fnt.glyphs[0].isValid);
	assert(fnt.glyphs[0].originalBytes(fnt) == [0x81, 0xff]);

	//
	// unused char: https://en.wikipedia.org/wiki/Windows-1252
	//
	// TODO(iconv): iconv's CP1252 lacks bytes 81, 8D, 8F, 90, and 9D
	// follow-up: check if any other charsets need a similar fix
	//
	// >According to the information on Microsoft's and the Unicode Consortium's
	//  websites, positions 81, 8D, 8F, 90, and 9D are unused; however, the
	//  Windows API MultiByteToWideChar maps these to the corresponding C1
	//  control codes. 
	//
	// we should do the same thing
	//
	// % printf '\x81' | iconv -f CP1252
	// iconv: illegal input sequence at position 0
	//
	cs = "CP1252";
	fnt = ParsedFont(0, false, [0x81], 5, cs);
	assert(!fnt.glyphs[0].isValid);
	assert(fnt.glyphs[0].originalBytes(fnt) == [0x81]);
	// same but with wide=true
	cs = "CP1252";
	fnt = ParsedFont(0, true, [0x81, 0], 5, cs);
	assert(!fnt.glyphs[0].isValid);
	assert(fnt.glyphs[0].originalBytes(fnt) == [0x81]);
}

unittest
{
	const(char)* cs;
	enum Invalid = "�";

	// SWF6+, unspecified single-byte
	auto fnt = ParsedFont(0, false, ['a', 'b', 0], 6, cs);
	assert(fnt.glyphText(0) == "a");
	assert(fnt.glyphText(1) == "b");
	assert(fnt.glyphText(2) == "\0");
	assert(fnt.glyphText(3) is null);
	// SWF6+, UTF-16
	fnt = ParsedFont(0, true, ['a', 0, 'b', 0], 6, cs);
	assert(fnt.glyphText(0) == "a");
	assert(fnt.glyphText(1) == "b");
	assert(fnt.glyphText(2) is null);
	// SWF5, legacy multi-byte charset
	cs = "CP932"; // Shift_JIS
	fnt = ParsedFont(0, true, ['a', 0, 'b', 0], 5, cs);
	assert(fnt.glyphText(0) == "a");
	assert(fnt.glyphText(1) == "b");
	assert(fnt.glyphText(2) is null);

	cs = "CP932"; // Shift_JIS
	fnt = ParsedFont(0, true, [0xa0, 0x82], 5, cs); // note: reverse order from hexdump
	assert(fnt.glyphText(0) == "あ");
	assert(fnt.glyphText(1) is null);

	// wide char without Wide flag
	cs = "CP932"; // Shift_JIS
	fnt = ParsedFont(0, false, [0x82, 0xa0, 'x'], 5, cs);
	assert(fnt.glyphText(0) == Invalid);
	assert(fnt.glyphText(1) == Invalid);
	assert(fnt.glyphText(2) == "x");

	// INVALID: not an actual multi-byte character
	cs = "CP932"; // Shift_JIS
	fnt = ParsedFont(0, true, ['a', 'a'], 5, cs);
	assert(fnt.glyphText(0) == Invalid);
	assert(fnt.glyphText(1) is null);

	// INVALID: multi-byte character spans cells
	// あ = 82 a0
	// input to iconv: ['a'-82], [a0-'b']
	cs = "CP932"; // Shift_JIS
	fnt = ParsedFont(0, true, [0x82, 'a', 'b', 0xa0], 5, cs);
	assert(fnt.glyphText(0) == Invalid); // "invalid argument", read 1/2 bytes
	assert(fnt.glyphText(1) == Invalid); // "invalid or incomplete ...", output 0 bytes
	assert(fnt.glyphText(2) is null);

	// TEST: incomplete MB char in first cell doesn't break the second one
	cs = "CP932"; // Shift_JIS
	fnt = ParsedFont(0, true, [0x82, 'a', '!', 0], 5, cs);
	assert(fnt.glyphText(0) == Invalid);
	assert(fnt.glyphText(1) == "!");
	fnt = ParsedFont(0, true, [0x82, 'a', 'a', 0], 5, cs);
	assert(fnt.glyphText(0) == Invalid);
	assert(fnt.glyphText(1) == "a");

	fnt = ParsedFont(0, true, [0x81, 'x', 0x81, 0x81], 5, cs);
	assert(fnt.glyphText(0) == Invalid);
	assert(fnt.glyphText(1) == "＝");
	fnt = ParsedFont(0, true, [0x81, 'x', 'y', 0x81], 5, cs);
	assert(fnt.glyphText(0) == Invalid);
	assert(fnt.glyphText(1) == "【");

	//explainBytes(cast(ubyte[])fnt.glyphText(1), (scope exp)
	//{
	//	printf("%.*s\n", cast(int)exp.length, exp.ptr);
	//});
}
