module swfbiganal.swf.textbuilder;

import swfbiganal.swf.fontglyphs;
import swfbiganal.swftypes.swftag;
import swfbiganal.util.appender;
import swfbiganal.util.compiler;

// puts together the text in a DefineText/DefineText2
struct TextBuilder
{
	const(SwfTag)*          tag;
	ParsedFont*             currentFont;
	ScopedAppender!(char[]) text;

	bool empty()
	{
		return (!text[].length);
	}

	void addNewline()
	{
		if (text[].length)
		{
			text ~= "\n";
		}
	}

	void setFont(ParsedFont* pf)
	{
		// http://127.1.1.1/dbtest.php?do=analyze&md5=4EE1F1D36327255762B616C892D717ED
		if (pf && expect(!pf.hasGlyphs, false))
		{
			(*tag).print("font %hu has no glyphs defined", pf.id);
			pf = null;
		}

		if (currentFont && currentFont != pf)
		{
			currentFont.checkGlyphs(*tag);
		}

		currentFont = pf;
	}

	void beforeAppendGlyphs(uint glyphCount)
	{
		text.reserve(glyphCount);
	}

	void afterAppendGlyphs()
	{
	}

	/**
	 * append a glyph from the current font to the text
	 */
	void appendGlyph(uint glyphIndex)
	{
		const(char)[] b = ParsedFont.replacementStr;
		if (expect(currentFont != null, true))
		{
			const(char)[] bs = currentFont.glyphText(glyphIndex);
			if (expect(bs.length != 0, true))
			{
				b = bs;
			}
			else
			{
				(*tag).print("font %hu has no glyph %u", currentFont.id, glyphIndex);
			}
		}
		text ~= b;
	}

	const(char)[] finalize()
	{
		if (currentFont)
		{
			currentFont.checkGlyphs(*tag);
			currentFont = null;
		}

		const(char)[] str = text[];

		// make sure we return non-null if some glyphs were written
		// fix: http://127.1.1.1/dbtest.php?do=analyze&md5=A5545A8015587AE1592E4A5BBADF3565&charset=CP1255
		// uh, but why is the string empty with this encoding? TODO
		if (!str.ptr && !empty)
		{
			str = "";
		}

		return str;
	}
}
