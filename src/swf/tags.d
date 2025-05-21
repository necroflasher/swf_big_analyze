module swfbiganal.swf.tags;

import core.stdc.stdio;
import swfbiganal.globals;
import swfbiganal.swfbitreader;
import swfbiganal.swfreader;
import swfbiganal.swftypes.swftag;
import swfbiganal.swftypes.swfshape;
import swfbiganal.swftypes.swfrect;
import swfbiganal.swftypes.swfmatrix;
import swfbiganal.swftypes.swfcolortransform;
import swfbiganal.swftypes.swfanyfilter;
import swfbiganal.swftypes.swfheader;
import swfbiganal.swftypes.swfrgb;
import swfbiganal.swf.errors;
import swfbiganal.swf.fontglyphs;
import swfbiganal.swf.strings;
import swfbiganal.swf.textbuilder;
import swfbiganal.swf.tagtimestat;
import swfbiganal.util.charconv;
import swfbiganal.util.explainbytes;
import swfbiganal.util.unhtml;
import swfbiganal.util.urlencode;
import swfbiganal.util.compiler;

struct TagParserState
{
	SwfReader*   reader;
	const(char)* defaultCharset;
	TagTimeStat* tagTimeStat;
	uint         spriteDepth;

	// function for main.d to print a tag
	// called for tags found inside sprites
	void function(ref const(SwfTag)) tagPrintFunc = (ref _){};

	SwfStrings strings;
	template getStringSet(SwfStrings.StringType type)
	{
		bool addNew(scope const(char)[] str)
		{
			return strings.addNew(str, type);
		}
		bool addNew(scope const(ubyte)[] str)
		{
			return strings.addNew(cast(char[])str, type);
		}
	}
	alias as2StringsSeen     = getStringSet!(SwfStrings.StringType.as2);           // DoAction, DoInitAction, DefineButton, DefineButton2, PlaceObject2, PlaceObject3
	alias as3StringsSeen     = getStringSet!(SwfStrings.StringType.as3);           // DoABC, DoABCDefine
	alias textStringsSeen    = getStringSet!(SwfStrings.StringType.text);          // DefineEditText
	alias textStringsSeen2   = getStringSet!(SwfStrings.StringType.text2);         // DefineText, DefineText2
	alias exportsSeen        = getStringSet!(SwfStrings.StringType.export_);       // Export
	alias objectsSeen        = getStringSet!(SwfStrings.StringType.object);        // PlaceObject2, PlaceObject3
	alias fontNamesSeen      = getStringSet!(SwfStrings.StringType.fontName);      // DefineFontName, DefineFontInfo, DefineFontInfo2
	alias fontCopyrightsSeen = getStringSet!(SwfStrings.StringType.fontCopyright); // DefineFontName
	alias frameLabelsSeen    = getStringSet!(SwfStrings.StringType.frameLabel);

	ParsedFont[ushort] parsedFontById;

	bool decodeText(const(ubyte)[] buf, ref SwfTag tag, scope void delegate(scope const(char)[]) cb)
	{
		if (reader.swfHeader.swfVersion >= 6)
		{
			cb(cast(char[])buf);
			return true;
		}
		else
		{
			const(char)* coding = "CP1252";
			if (defaultCharset)
			{
				coding = defaultCharset;
			}
			bool ok = buf.transmute(coding, "UTF-8", (scope buf)
			{
				cb(cast(char[])buf);
			});
			if (!ok)
			{
				// http://127.1.1.1/dbtest.php?do=analyze&md5=96D689FAA493852B863ED289DDC6D179
				explainBytes(buf, (scope exp)
				{
					tag.print("failed to decode string as %s: %.*s",
						coding,
						cast(int)exp.length, exp.ptr);
				});
			}
			return ok;
		}
	}

	void addFont(
		ref SwfTag tag,
		ushort id,
		bool isWide,
		scope const(ubyte)[] mapBytes,
		ref TagParserState ps)
	{
		parsedFontById.update(id,
			() {
				return ParsedFont(
					id,
					isWide,
					mapBytes,
					ps.reader.swfHeader.swfVersion,
					defaultCharset,
				);
			},
			(ref ParsedFont old) {
				// don't replace an existing font if we get a DefineFont for it (it has no glyphs)
				// http://127.1.1.1/dbtest.php?do=analyze&md5=2316B33014E9FC0A9AA9085479682A0E
				if (tag.code == SwfTagCode.DefineFont)
				{
					assert(mapBytes is null);
					return;
				}

				if (!old.hasGlyphs)
				{
					old = ParsedFont(
						id,
						isWide,
						mapBytes,
						ps.reader.swfHeader.swfVersion,
						defaultCharset,
					);
					return;
				}

				// uh TODO: is this meant to skip or replace the font?
				// skipping is faster so i'll do that now
				// replaced with same glyph count: http://127.1.1.1/dbtest.php?do=analyze&md5=D71A008FB5799634D2128B64FC38BF81
				tag.print("font %hu already exists, skipping", id);
			});
	}
}

void readTag(ref TagParserState parserState, ref SwfTag tag, ref bool gotEndTag)
{
	if (expect(parserState.tagTimeStat != null, false))
		parserState.tagTimeStat.start();

	switch (tag.code)
	{
		case SwfTagCode.End: // 0
		{
			gotEndTag = true;
			break;
		}
		case SwfTagCode.DefineButton: // 7
		{
			readDefineButton(parserState, tag);
			break;
		}
		case SwfTagCode.SetBackgroundColor: // 9
		{
			readSetBackgroundColor(tag);
			break;
		}
		case SwfTagCode.DefineFont: // 10
		{
			readDefineFont(parserState, tag);
			break;
		}
		case SwfTagCode.DefineText:  // 11
		case SwfTagCode.DefineText2: // 33
		{
			readDefineText(parserState, tag);
			break;
		}
		case SwfTagCode.DoAction:     // 12
		case SwfTagCode.DoInitAction: // 59
		{
			readDoAction(parserState, tag);
			break;
		}
		case SwfTagCode.DefineFontInfo:  // 13
		case SwfTagCode.DefineFontInfo2: // 62
		{
			readDefineFontInfo(parserState, tag);
			break;
		}
		case SwfTagCode.DefineSound: // 14
		{
			if (tag.data.length > 7)
			{
				parseSoundData(tag.data[7..$], tag);
			}
			break;
		}
		case SwfTagCode.SoundStreamBlock: // 19
		{
			parseSoundData(tag.data, tag);
			break;
		}
		case SwfTagCode.PlaceObject2: // 26
		case SwfTagCode.PlaceObject3: // 70
		{
			readPlaceObject2(parserState, tag);
			break;
		}
		case SwfTagCode.DefineButton2: // 34
		{
			readDefineButton2(parserState, tag);
			break;
		}
		case SwfTagCode.DefineEditText: // 37
		{
			readDefineEditText(parserState, tag);
			break;
		}
		case SwfTagCode.DefineSprite: // 39
		{
			readDefineSprite(parserState, tag);
			break;
		}
		case SwfTagCode.FrameLabel: // 43
		{
			readFrameLabel(parserState, tag);
			break;
		}
		case SwfTagCode.DefineFont2: // 48
		case SwfTagCode.DefineFont3: // 75
		{
			readDefineFont2(parserState, tag);
			break;
		}
		case SwfTagCode.Export: // 56
		{
			readExport(parserState, tag);
			break;
		}
		case SwfTagCode.Import:  // 57
		case SwfTagCode.Import2: // 71
		{
			readImport(parserState, tag);
			break;
		}
		case SwfTagCode.FileAttributes: // 69
		{
			readFileAttributes(parserState, tag);
			break;
		}
		case SwfTagCode.DoABCDefine: // 72
		case SwfTagCode.DoABC:       // 82
		{
			readDoABC(parserState, tag);
			break;
		}
		case SwfTagCode.SymbolClass: // 76
		{
			readSymbolClass(tag);
			break;
		}
		case SwfTagCode.Metadata: // 77
		{
			readMetadata(tag);
			break;
		}
		case SwfTagCode.DefineSceneAndFrameData: // 86
		{
			readDefineSceneAndFrameData(tag);
			break;
		}
		case SwfTagCode.DefineBinaryData: // 87
		{
			readDefineBinaryData(tag);
			break;
		}
		case SwfTagCode.DefineFontName: // 88
		{
			readDefineFontName(parserState, tag);
			break;
		}
		default:
		{
			return;
		}
	}

	if (expect(parserState.tagTimeStat != null, false))
		parserState.tagTimeStat.end(tag.code);
}

// -----------------------------------------------------------------------------

private:

// https://www.m2osw.com/swf_tag_definebutton
void readDefineButton(ref TagParserState ps, ref SwfTag tag)
in (tag.code == SwfTagCode.DefineButton) // 7
{
	auto br = SwfBitReader(tag.data);
	br.skip!ushort; // buttonId
	parseSwfButtons(br, ps, tag);
	parseActionBytes(ps, br.readRemaining, tag);
	br.finish(tag);
}

void readSetBackgroundColor(ref SwfTag tag)
in (tag.code == SwfTagCode.SetBackgroundColor) // 9
{
	auto br = SwfBitReader(tag.data);
	auto color = SwfRgb(br);
	br.finish(tag);
	if (!br.overflow)
	{
		printf("!background-color #%02hhx%02hhx%02hhx\n", color.r, color.g, color.b);
	}
}

// https://www.m2osw.com/swf_tag_definefont
void readDefineFont(ref TagParserState ps, ref SwfTag tag)
in (tag.code == SwfTagCode.DefineFont) // 10
{
	auto br = SwfBitReader(tag.data);

	uint fontId = br.read!ushort;

	// nothing useful here, and shapes are complex to parse
	if (0)
	{
		// i wonder how this is meant to work
		uint glyphCount;
		{
			ulong startBit = br.curBit;
			glyphCount = (br.read!ushort / 2);
			if (!br.overflow)
			{
				br.curBit = startBit;
			}
		}

		br.skipBytes(glyphCount*ushort.sizeof); // offsets

		foreach (_; 0..glyphCount)
		{
			SwfShape.skip(br, tag);
		}

		br.finish(tag);
	}
	else
	{
		br.finishIncomplete(tag);
	}

	if (!br.overflow)
	{
		ps.addFont(tag, cast(ushort)fontId, false, null, ps);
	}
}

// https://www.m2osw.com/swf_tag_definetext
// https://www.m2osw.com/swf_tag_definetext2
void readDefineText(ref TagParserState ps, ref SwfTag tag)
in (
	tag.code == SwfTagCode.DefineText || // 11
	tag.code == SwfTagCode.DefineText2)  // 33
{
	auto br = SwfBitReader(tag.data);

	br.skip!ushort; // textId
	SwfRect.skip(br);
	SwfMatrix.skip(br);
	uint glyphBits   = br.read!ubyte; // normally 0-16
	uint advanceBits = br.read!ubyte; // normally 0-16

	ParsedFont* currentFont;
	TextBuilder tb = {tag: &tag};
	bool didSetFont;
	uint maxGlyphsPerLine;

	for (;;)
	{
		uint flags = br.read!ubyte;

		enum First    = 0b1000_0000;
		enum Reserved = 0b0111_0000;
		enum HasFont  = 1<<3;
		enum HasColor = 1<<2;
		enum HasMoveY = 1<<1;
		enum HasMoveX = 1<<0;

		if (flags == 0)
		{
			break;
		}

		// warn for this because it would complicate the stop logic
		if (expect((flags & Reserved) != 0, false))
		{
			tag.print("text record has reserved bits set");
		}

		if (flags & HasFont)
		{
			uint fontId = br.read!ushort;
			ParsedFont* pf = (cast(ushort)fontId in ps.parsedFontById); 
			tb.setFont(pf);
			didSetFont = true;
			if (expect(!pf, false))
			{
				tag.print("font %u not found", fontId);
			}
		}

		if (flags & (HasColor|HasMoveX|HasMoveY|HasFont))
		{
			uint bytes;
			if (flags & HasColor)
			{
				bytes += 3 + (tag.code == SwfTagCode.DefineText2);
			}
			if (flags & (HasMoveX|HasMoveY|HasFont))
			{
				uint count = (
					!!(flags & HasMoveX) +
					!!(flags & HasMoveY) +
					!!(flags & HasFont) // font's height
				);
				bytes += ( count * ushort.sizeof );
			}
			br.skipBytes(bytes);
		}

		uint glyphCount = br.read!ubyte;

		if (expect(glyphCount != 0, true))
		{
			if (expect(!didSetFont, false))
			{
				tag.print("writing glyphs with no font set");
			}

			if (glyphCount > maxGlyphsPerLine)
			{
				maxGlyphsPerLine = glyphCount;
			}

			// detect when it's meant to start a new line vs. just change the style
			// http://127.1.1.1/dbtest.php?do=analyze&md5=46E2C29C50FBBD0B8C8C3FD5A84F897E
			// http://127.1.1.1/dbtest.php?do=analyze&md5=BF351DAC73BC0A911A8BE675E2C15436
			if ((flags & (HasMoveX|HasMoveY)) != 0 && !tb.empty)
			{
				tb.addNewline();
			}

			tb.beforeAppendGlyphs(glyphCount);
			foreach (_; 0..glyphCount)
			{
				// https://www.m2osw.com/swf_struct_text_entry
				uint glyphIndex = br.readUB(glyphBits);
				br.skipBits(advanceBits);
				tb.appendGlyph(glyphIndex);
			}
			tb.afterAppendGlyphs();
		}
	}

	br.finish(tag);

	// bytes left: http://127.1.1.1/dbtest.php?do=analyze&md5=59356D6C1986E5A65A045A424F655827
	// don't know why, everything seems to be parsed correctly

	// overflow (corrupt tag?): http://127.1.1.1/dbtest.php?do=analyze&md5=296082F962A6918A0A55020BD0E0ED6D

	static if (GlobalConfig.OutputStrings)
	{
		if (!tb.empty)
		{
			char[] text = cast(char[])tb.finalize();
			if (text !is null && ps.textStringsSeen2.addNew(text))
			{
				// re-orient vertical text
				// https://stackoverflow.com/a/9895318
				static char[] removeEmbeddedNewlines(char[] text)
				{
					size_t outidx;
					foreach (i, c; text)
					{
						text[outidx] = c;
						if (c != '\n')
						{
							outidx++;
						}
					}
					return text[0..outidx];
				}
				static assert(removeEmbeddedNewlines("".dup) == "");
				static assert(removeEmbeddedNewlines("\n".dup) == "");
				static assert(removeEmbeddedNewlines("abc".dup) == "abc");
				static assert(removeEmbeddedNewlines("\na\nb\nc\n".dup) == "abc");
				if (maxGlyphsPerLine == 1)
				{
					text = removeEmbeddedNewlines(text);
				}
				urlEncodeMin(text, (scope s)
				{
					printf("!text-string2 %.*s\n", cast(int)s.length, s.ptr);
				});
			}
		}
	}
}

// https://www.m2osw.com/swf_tag_doaction
// https://www.m2osw.com/swf_tag_doinitaction
void readDoAction(ref TagParserState ps, ref SwfTag tag)
in (
	tag.code == SwfTagCode.DoAction ||   // 12
	tag.code == SwfTagCode.DoInitAction) // 59
{
	auto br = SwfByteReader(tag.data);
	if (tag.code == SwfTagCode.DoInitAction)
	{
		br.skip!ushort; // spriteId
	}
	parseActionBytes(ps, br.readRemaining, tag);
	br.finish(tag);
}

// https://www.m2osw.com/swf_tag_definefontinfo
void readDefineFontInfo(ref TagParserState ps, ref SwfTag tag)
in (
	tag.code == SwfTagCode.DefineFontInfo || // 13
	tag.code == SwfTagCode.DefineFontInfo2)  // 62
{
	auto br = SwfBitReader(tag.data);

	ushort         fontId         = cast(ushort)br.read!ushort;
	uint           fontNameLength = br.read!ubyte;
	const(ubyte)[] fontName       = br.readBytesNoCopy(fontNameLength);
	uint           flags          = br.read!ubyte;

	while (fontName.length && fontName[$-1] == 0)
	{
		fontName = fontName[0..$-1];
	}
	static if (GlobalConfig.OutputStrings)
	{
		if (fontName.length)
		{
			// needs decode: http://127.1.1.1/dbtest.php?do=analyze&md5=9BD2E8EE47B6FB03B8EF8437BDF440DF&charset=CP932
			// NOTE: dedupe as utf-8 because the other tag that gives this is always utf-8
			ps.decodeText(fontName, tag, (scope str)
			{
				if (ps.fontNamesSeen.addNew(str))
				{
					urlEncodeMin(str, (scope s)
					{
						printf("!font-name %.*s\n", cast(int)s.length, s.ptr);
					});
				}
			});
		}
	}

	enum Wide = 1<<0;

	int lang = -1;
	if (ps.reader.swfHeader.swfVersion >= 6 && tag.code == SwfTagCode.DefineFontInfo2)
	{
		lang = br.read!ubyte;
	}

	bool isUnicode = true;
	bool isShiftJis;
	bool isAnsii; // wtf
	if (!(ps.reader.swfHeader.swfVersion >= 6 && tag.code == SwfTagCode.DefineFontInfo2))
	{
		isUnicode  = !!(flags & (1<<5));
		isShiftJis = !!(flags & (1<<4));
		isAnsii    = !!(flags & (1<<3));
	}
	const(ubyte)[] mapBytes = br.readRemaining;

	if (!br.overflow)
	{
		// mapBytes containing wide chars must have an even length in bytes
		if ((flags & Wide) != 0 && (mapBytes.length % 2) != 0)
		{
			mapBytes = mapBytes[0..$-1];
		}

		ps.addFont(
			tag,
			fontId,
			!!(flags & Wide),
			mapBytes,
			ps,
			);
	}

	br.finish(tag);
}

void readPlaceObject2(ref TagParserState ps, ref SwfTag tag)
in (
	tag.code == SwfTagCode.PlaceObject2 || // 26
	tag.code == SwfTagCode.PlaceObject3)   // 70
{
	auto br = SwfBitReader(tag.data);

	// NOTE: this is the most common tag of the ones parsed. it should be optimized accordingly

	// NOTE: where the docs say "version >= 8" is actually specific to the PlaceObject3 version of the struct
	// check ffdec for the actual flags and structure of PlaceObject3

	// PO2 swf10 no flags8: http://127.1.1.1/dbtest.php?do=analyze&md5=7D4560415141CDD6D46D25E495705C1C
	// PO2 swf9 no flags8: http://127.1.1.1/dbtest.php?do=analyze&md5=199402C67FF96BB0A50FA5EDA5B561E0
	// PO2 swf4 no flags8: http://127.1.1.1/dbtest.php?do=analyze&md5=07CCE8543984A47B939516C200701566
	// PO3 swf8 yes flags8: http://127.1.1.1/dbtest.php?do=analyze&md5=3D02D62146D8581980EB4951EE4B7402
	uint flags = (tag.code == SwfTagCode.PlaceObject3) ? br.read!ushort : br.read!ubyte;

	enum HasActions        = 1<<7; // swf5+?
	enum HasClippingDepth  = 1<<6;
	enum HasName           = 1<<5;
	enum HasMorphPosition  = 1<<4;
	enum HasColorTransform = 1<<3;
	enum HasMatrix         = 1<<2;
	enum HasIdRef          = 1<<1; // ffdec: HasCharacter
	enum HasMove           = 1<<0;

	/*uint depth =*/ br.skipBits(16);

	if (flags & HasIdRef) // ffdec characterId
	{
		br.skipBits(16);
	}
	if (flags & HasMatrix) // ffdec matrix
	{
		SwfMatrix.skip(br);
	}
	if (flags & HasColorTransform)
	{
		SwfColorTransform.skipWithAlpha(br, tag);
	}
	if (flags & HasMorphPosition)
	{
		br.skipBits(16);
	}
	if (flags & HasName)
	{
		// needs decode: http://127.1.1.1/dbtest.php?do=analyze&md5=93F2DC0146D901FC312137E04E7F37B5&charset=CP932
		const(ubyte)[] nameBytes = br.readNullTerminatedBytes();
		static if (GlobalConfig.OutputStrings)
		{
			if (nameBytes.length && ps.objectsSeen.addNew(nameBytes))
			{
				ps.decodeText(nameBytes, tag, (scope name)
				{
					urlEncodeMin(name, (scope s)
					{
						printf("!object-name %.*s\n", cast(int)s.length, s.ptr);
					});
				});
			}
		}
	}
	if (flags & HasClippingDepth)
	{
		br.skipBits(16);
	}

	if (tag.code == SwfTagCode.PlaceObject3)
	{
		enum Reserved          = 1<<15;
		enum OpaqueBackground  = 1<<14; // xxx: doc says reserved, name from ffdec
		enum HasVisible        = 1<<13; // (no doc, implemented based on ffdec)
		enum HasImage          = 1<<12; // xxx: doc says reserved, name from ffdec
		enum HasClassName      = 1<<11; // xxx: doc says reserved, name from ffdec
		enum HasCacheAsBitmap  = 1<<10; // (doc unsure about this but it works)
		enum HasBlendMode      = 1<<9;
		enum HasFilterList     = 1<<8;

		if (flags & HasFilterList)
		{
			// https://www.m2osw.com/swf_struct_any_filter
			uint filterCount = br.read!ubyte;
			foreach (_; 0..filterCount)
			{
				SwfAnyFilter.skip(br, tag);
			}
		}
		if (flags & HasBlendMode)
		{
			br.skipBits(8);
		}
		if (flags & HasCacheAsBitmap) // ffdec bitmapCache
		{
			// align first to fix http://127.1.1.1/dbtest.php?do=analyze&md5=1777BEA63603143BA9AD2833546D9E1F
			br.byteAlign();
			if (br.empty && !br.overflow)
			{
				// ?
				// http://127.1.1.1/dbtest.php?do=analyze&md5=D30C3E8E8398BC8A2D23AE74E69F107D
				// http://127.1.1.1/dbtest.php?do=analyze&md5=7907A5F124E359F3916C226B2FA92EE1
				// http://127.1.1.1/dbtest.php?do=analyze&md5=1777BEA63603143BA9AD2833546D9E1F
				return;
			}
			br.skipBits(8);
		}
		if (flags & HasClassName)
		{
			// XXX: guessed position, seen no flashes with this
			tag.print("unimplemented flag HasClassName");
		}
		if (flags & HasImage)
		{
			// XXX: guessed position
			// doesn't seem to add anything to parse in ffdec?
			// http://127.1.1.1/dbtest.php?do=analyze&md5=4EF97EB6B5824D3AAABC0C4E1367C823
			//tag.print("unimplemented flag HasImage");
		}
		if (flags & HasVisible) // ffdec visible
		{
			// note: not documented, logic from ffdec
			// fixes: http://127.1.1.1/dbtest.php?do=analyze&md5=0B53EC86089A8FFB619B0A7C7CDB2D30
			br.skipBits(8);
		}
	}

	if (flags & HasActions) // ffdec clipActions
	{
		bool wideFlags = (ps.reader.swfHeader.swfVersion >= 6);
		uint flagBits = wideFlags ? 32 : 16;
		br.skipBits(16 + flagBits); // reserved + allFlags

		// swf5 ok: http://127.1.1.1/dbtest.php?do=analyze&md5=23E550300D5BA036A994534ECA0A8525
		// ^ object monkey, string endGoodTime
		// swf7 ok: http://127.1.1.1/dbtest.php?do=analyze&md5=0310559F917C191958FCE1D2777693BD
		// ^ object boundingBox_mc, strings selected toggle enabled ...
		while (!br.empty)
		{
			uint eventFlags = wideFlags ? br.read!uint : br.read!ushort;
			if (eventFlags == 0)
			{
				break;
			}
			uint eventLength = br.read!uint;
			const(ubyte)[] actionBytes = br.readBytesNoCopy(eventLength);
			parseActionBytes(ps, actionBytes, tag);
		}
	}

	br.finish(tag);
}

// https://www.m2osw.com/swf_tag_definebutton2
void readDefineButton2(ref TagParserState ps, ref SwfTag tag)
in (tag.code == SwfTagCode.DefineButton2) // 34
{
	auto br = SwfBitReader(tag.data);

	uint buttonId    = br.read!ushort;

	uint flags       = br.read!ubyte;
	uint buttonsSize = br.read!ushort;

	// no buttons but has AS: http://127.1.1.1/dbtest.php?do=analyze&md5=50FB4639460FD450C075D01FF681D224
	// (^ or was this just zero buttonsSize? didn't check the hex dump)
	// hm - docs say, if there are no conditions (meaning AS), this will be zero
	// but should i trust that?
	parseSwfButtons(br, ps, tag);

	// https://www.m2osw.com/swf_struct_condition
	// argh, this is actually an array thing (read the description)
	// test file, has buttons with both 1 and more conditions here:
	// http://127.1.1.1/dbtest.php?do=analyze&md5=BC2DAB2F27D148A397DBE27A0D83FADE
	// doc was useless, this is based on what i see in ffdec
	while (!br.empty)
	{
		uint condLen = br.read!ushort;
		uint condFlags = br.read!ushort;
		parseActionBytes(ps, condLen ? br.readBytesNoCopy(condLen-4) : br.readRemaining, tag);
		if (!condLen)
		{
			break;
		}
	}

	br.finish(tag);
}

// https://www.m2osw.com/swf_tag_defineedittext
void readDefineEditText(ref TagParserState ps, ref SwfTag tag)
in (tag.code == SwfTagCode.DefineEditText) // 37
{
	auto br = SwfBitReader(tag.data);

	// bit field layout:
	// first 8: bits 7->0
	// next 8: bits 15->8
	// and so on

	enum HasText      = 1<<7;
	enum HasColor     = 1<<2;
	enum HasMaxLength = 1<<1;
	enum HasFont      = 1<<0;
	enum HasLayout    = 1<<13;
	enum Html         = 1<<9;

	br.skip!ushort;
	SwfRect.skip(br);
	uint flags = br.read!ushort;
	if (flags & (HasFont|HasColor|HasMaxLength|HasLayout))
	{
		uint byteCount;
		if (flags & HasFont)      byteCount += 2*ushort.sizeof;
		if (flags & HasColor)     byteCount += 4*ubyte.sizeof;
		if (flags & HasMaxLength) byteCount += 1*ushort.sizeof;
		if (flags & HasLayout)    byteCount += 1*ubyte.sizeof + 4*ushort.sizeof;
		br.skipBytes(byteCount);
	}
	br.readNullTerminatedBytes();

	if (flags & HasText)
	{
		const(ubyte)[] text = br.readNullTerminatedBytes();

		scope putText = (scope const(ubyte)[] text)
		{
			static if (GlobalConfig.OutputStrings)
			{
				if (text.length && ps.textStringsSeen.addNew(text))
				{
					// needs decode: http://127.1.1.1/dbtest.php?do=analyze&md5=B57DEF6F520C4ABF4F30BA105AB190FD&charset=CP932
					ps.decodeText(text, tag, (scope textUtf)
					{
						urlEncodeMin(textUtf, (scope s)
						{
							printf("!%s-string %.*s\n",
								(flags & Html) ? "html".ptr : "text".ptr,
								cast(int)s.length, s.ptr);
						});
					});
				}
			}
		};

		if (flags & Html)
		{
			unhtml(cast(char[])text, (scope s)
			{
				putText(cast(ubyte[])s);
			});
		}
		else
		{
			while (text.length && text[$-1] <= ' ')
			{
				text = text[0..$-1];
			}
			putText(text);
		}
	}

	// old TODO: look at flashes that have extra data here
	br.finishIncomplete(tag);
}

// https://www.m2osw.com/swf_tag_definesprite
void readDefineSprite(ref TagParserState ps, ref SwfTag tag)
in (tag.code == SwfTagCode.DefineSprite) // 39
{
	if (expect(GlobalConfig.OutputTags, false))
	{
		printf("!begin-sprite\n");
	}

	if (ps.spriteDepth++)
	{
		// 10 of 40k local flashes have this, all with max depth 2

		// 4plebs/1414/46/1414460953093.swf
		// 4plebs/1437/18/1437182340838.swf
		// 4plebs/1437/26/1437267041697.swf
		// 4plebs/1437/34/1437348272663.swf
		// 4plebs/1437/53/1437531582459.swf
		// 4plebs/1438/61/1438613296621.swf
		// 4plebs/1438/63/1438636739169.swf
		// 4plebs/1438/81/1438813124246.swf
		// 4plebs/1438/86/1438869006333.swf
		// 4plebs/1454/52/1454528478630.swf

		tag.print("nested sprite (depth %u)", ps.spriteDepth);
	}

	auto br = SwfByteReader(tag.data);

	br.skipBits(32); // spriteId, frameCount

	// swf data offset where this tag's data begins
	// adding br.offset to this gives the current offset in swf data
	ulong baseOffset
		= tag.fileOffset
		+ (tag.longFormat ? 2+4 : 2);

	bool gotEndTag;

	while (!br.empty)
	{
		size_t tagBeginOffset = br.curByte;

		uint   x      = br.read!ushort;
		uint   code   = x >> 6;
		size_t length = x & 0b111111;

		bool longFormat;
		if (length == 0x3f)
		{
			longFormat = true;
			length = br.read!uint;
		}

		const(ubyte)[] tagData = br.readBytesNoCopy(length);

		if (br.overflow)
		{
			break;
		}

		SwfTag parsedTag = {
			code:       code,
			data:       tagData,
			longFormat: longFormat,
			fileOffset: baseOffset + tagBeginOffset,
		};

		if (expect(GlobalConfig.OutputTags, false))
		{
			ps.tagPrintFunc(parsedTag);
		}

		readTag(ps, parsedTag, gotEndTag);

		if (gotEndTag)
		{
			break;
		}
	}

	// bytes left: http://127.1.1.1/dbtest.php?do=analyze&md5=0A0D5552620F9A3BA2D6FA91F85070C6
	// ignore them
	br.finishIncomplete(tag);

	if (!br.overflow && !gotEndTag)
	{
		tag.print("no end tag");
	}

	if (!ps.spriteDepth--)
		assert(0); // underflow

	if (expect(GlobalConfig.OutputTags, false))
	{
		printf("!end-sprite\n");
	}
}

// https://www.m2osw.com/swf_tag_framelabel
void readFrameLabel(ref TagParserState ps, ref SwfTag tag)
in (tag.code == SwfTagCode.FrameLabel) // 43
{
	// needs decode: http://127.1.1.1/dbtest.php?do=analyze&md5=3D76671547BC79E00B3CAB16AFB2F1BC&charset=CP932
	// lol http://127.1.1.1/dbtest.php?do=analyze&md5=036CE1C899E7C8CAB6EE15BD078C3093
	auto br = SwfByteReader(tag.data);

	const(ubyte)[] nameBytes = br.readNullTerminatedBytes();

	// http://127.1.1.1/dbtest.php?do=analyze&md5=01A39AB998888988B1D197C6E47DFFE1
	// http://127.1.1.1/dbtest.php?do=analyze&md5=E0A593BF2079998DB8B658B334FB39A6
	if (!br.empty)
	{
		// note: docs say this is ushort, i've only seen it as ubyte
		br.skip!ubyte; // flags
	}

	static if (GlobalConfig.OutputStrings)
	{
		if (nameBytes.length && ps.frameLabelsSeen.addNew(nameBytes))
		{
			ps.decodeText(nameBytes, tag, (scope name)
			{
				urlEncodeMin(name, (scope s)
				{
					printf("!frame-label %.*s\n", cast(int)s.length, s.ptr);
				});
			});
		}
	}

	br.finish(tag);
}

// https://www.m2osw.com/swf_tag_definefont2
// https://www.m2osw.com/swf_tag_definefont3
void readDefineFont2(ref TagParserState ps, ref SwfTag tag)
in (
	tag.code == SwfTagCode.DefineFont2 || // 48
	tag.code == SwfTagCode.DefineFont3)   // 75
{
	enum HasLayout   = 1<<7;
	enum WideOffsets = 1<<3;
	enum WideChars   = 1<<2;

	auto br = SwfBitReader(tag.data);

	// https://www.m2osw.com/swf_tag_definefont3
	ushort         fontId     = cast(ushort)br.read!ushort;
	uint           flags      = br.read!ubyte;
	uint           lang       = br.read!ubyte;
	uint           nameLength = br.read!ubyte;
	const(ubyte)[] fontName   = br.readBytesNoCopy(nameLength);
	uint           glyphCount = br.read!ushort;

	// fix dedupe: http://127.1.1.1/dbtest.php?do=analyze&md5=D0C4549536221644867A1E4CBEA9B33D
	while (fontName.length && fontName[$-1] == 0)
	{
		fontName = fontName[0..$-1];
	}
	static if (GlobalConfig.OutputStrings)
	{
		if (fontName.length)
		{
			// normal: http://127.1.1.1/dbtest.php?do=analyze&md5=97C91D099563E3C2476177A526C2A8B4
			// sjis: http://127.1.1.1/dbtest.php?do=analyze&md5=FA760A3ED5F7EB1B5DEE6F87C17C50E2&charset=CP932
			// NOTE: dedupe as utf-8 to match the other tag that gives !font-name which is always utf-8
			ps.decodeText(fontName, tag, (scope str)
			{
				if (ps.fontNamesSeen.addNew(str))
				{
					urlEncodeMin(str, (scope s)
					{
						printf("!font-name %.*s\n", cast(int)s.length, s.ptr);
					});
				}
			});
		}
	}

	// no glyphs!
	// return early so we don't overflow on the offsets thing
	// http://127.1.1.1/dbtest.php?do=md5info&md5=218B5E460D5BB1177156983AA5C62E10
	if (!glyphCount)
	{
		// many flashes still have 2 bytes left here
		// http://127.1.1.1/dbtest.php?do=analyze&md5=50FB4639460FD450C075D01FF681D224
		// http://127.1.1.1/dbtest.php?do=analyze&md5=5C6D27A2671377CBB0CDDBA3C5D7F060
		if (br.bitsLeft == 16)
		{
			br.skipBits(16);
		}
		br.finish(tag);
		return;
	}

	// offsetBytes, mapOffset
	br.skipBits((glyphCount+1)*((flags & WideOffsets) ? 32 : 16));

	foreach (_; 0..glyphCount)
	{
		SwfShape.skip(br, tag);
	}

	const(ubyte)[] mapBytes = br.readBytesNoCopy(
		glyphCount*(
			(flags & WideChars) ? ushort.sizeof : ubyte.sizeof));

	// if we got this far, save the font
	// http://127.1.1.1/dbtest.php?do=analyze&md5=53109A4F4EE385FE276B6B50310F45B0
	if (!br.overflow)
	{
		ps.addFont(
			tag,
			fontId,
			!!(flags & WideChars),
			mapBytes,
			ps,
			);
	}

	if (flags & HasLayout)
	{
		// ascent, descent, leadingHeight, then 1 ushort for each glyph
		br.skipBytes((3+glyphCount)*ushort.sizeof);

		// may end here: http://127.1.1.1/dbtest.php?do=analyze&md5=53109A4F4EE385FE276B6B50310F45B0
		if (!br.empty)
		{
			foreach (_; 0..glyphCount)
			{
				SwfRect.skip(br);
			}
			// docs say this is SWF8+ (is it?)
			if (!br.empty)
			{
				uint kerningCount = br.read!ushort;
				if (kerningCount & (1<<15))
				{
					// this is meant to be signed
					tag.print("signed kerningCount has top bit set");
				}
				// XXX: is this meant to use WideChars or the other wide flag?
				// these are glyph indices, not chars.....
				br.skipBytes( kerningCount*( ( (flags & WideChars) ? 2*ushort.sizeof : 2*ubyte.sizeof ) + ushort.sizeof ) );
			}
		}
	}

	br.finish(tag);
}

void readExport(ref TagParserState ps, ref SwfTag tag)
in (tag.code == SwfTagCode.Export) // 56
{
	auto br = SwfByteReader(tag.data);

	// examples
	// http://127.1.1.1/dbtest.php?do=analyze&md5=321C9A3A6876D7D7B3BE1399BFB85188
	// http://127.1.1.1/dbtest.php?do=analyze&md5=50FB4639460FD450C075D01FF681D224

	// needs decode:
	// http://127.1.1.1/dbtest.php?do=analyze&md5=30D7D01A551D02687BD53268D9F2F6A6&charset=CP932

	uint count = br.read!ushort;
	foreach (_; 0..count)
	{
		uint           objectId  = br.read!ushort;
		const(ubyte)[] nameBytes = br.readNullTerminatedBytes();

		static if (GlobalConfig.OutputStrings)
		{
			if (nameBytes.length && ps.exportsSeen.addNew(nameBytes))
			{
				ps.decodeText(nameBytes, tag, (scope name)
				{
					urlEncodeMin(name, (scope s)
					{
						printf("!export %.*s\n", cast(int)s.length, s.ptr);
					});
				});
			}
		}
	}

	if (!br.empty)
	{
		if (br.bytesLeft >= 242 && br.bytesLeft <= 248)
		{
			// BBD4C1AE48E7A27C7FF34886D22DAF75
			// 7FC0889114C59D1EA11C4D5686F40161
			// 6527BDDC1CF4B45CD57BDD34984A4ADF
			// 91FC8BBCE71F7FD70184F235B7DE8937
			// E75A2FF9D33A5E0CF1D41F1305B5B41A
			// 6B43ACF117F002DA00DC25DB8D3497F4
			// 489DE16CC8879E23CFEADBB9E90535F3
			// AEC3F7E63DE9FCD70E463835F8AB4A5A
			// 88E48335E6C5BFA90E8FC2706E7AF768
			// C3E8226BDA2FFB0774D404704BCBED33
			// 96E0D6A7B0B7CFDBA9387990DC79484D
			// 2F484E487A8A2BDE24D48327BE39AF42
			// 4AD3985547EECF1DECFBAE765FE2CF42
			// 14FA003448F3301CCE40583D8540FCAD
			// 2DF7FEFAFD509B161BF58182E488BCC9
			// FD71748C02C79798CB39664C7791AC42
			// 80A45F165832BC4516774EB83A58822E
			// F760BA80E192B2E73195A78787444727
			// 8F2EB7BB63DFBDD180428C0FA1D0099B
			// 83EE9CB9E4E300BBC1952BCD201D9C08
			// A9E7BD078F695F57484C4C8D69E83B63
			// D253AEAEF44F1E3BE73F97105204B599
			// BC31B7EC56215C599F06326A3AA6E10E
			// B692A7F339B5D0DF5CD370522F93D362
			// 244D3F1F914D7903CAD68E3AF968D715
			// DAE128DC94191B32D18C81955743FB9D
			// 76E4A663B089C6831D7E6CA92248A74D
			// CBA1BB276BAB043758AD4ACE74D2A484
			// 0BDCE6F3E40A441134BD286B6A1FAC66
			// B555373D74F9CD3BB072ACA3DFFAC5CC
			// 6873EFB3D1326AAE6696BDFC44A76BA2
			// B569C0F334720A1EE1B9A670394637ED
			// 784148F363E58727AD35B22717366DD1
			// B736B875310D72EDA83F6A8EE4216052
			// 05565E26EC4230233D145710DE5369FF
			// 33716E5248ACD15309E3FAB95675F3D5
			// C50FD1ACE301324A40956DC05A1A24B0
			// DA73A152529B1B87E10EE4E322476069
			// 7A1EC32A25D5301D20A04702D879D21D

			uint bits;
			foreach (b; br.remaining)
			{
				bits |= b;
			}
			if (bits == 0)
			{
				br.readRemaining;
			}
		}
		else if (br.bytesLeft == 2)
		{
			// 7B2A3AA01432A0394D8ADFDAC585D1B9
			// A4BEE9C23889F9D12E39C9FF094F45EF
			// F9BA4C152BB87EB64240426A095222FE
			// 260E0B5AB65A0EADE8F93AA9D64DC96F
			// 48F550636C8A4FBB5ADB6C88CD0A09F0
			// D4A74D2717F0712517FF51E7EE584DD1
			// 689CF966956E4CC29466DB13172FBE03
			// 73D3B9C80F786BCDB343FC6E108FECD4
			// F967D80E9FB95CF976BAFF75E9EDC418
			// 158FC0FD7B8397E329D7E52A5A977318
			// F13E3F2FF1788BF1283DBAF55380B722

			br.skip!ushort;
		}
		else if (br.bytesLeft >= 512 && br.remaining[0] == 0x88)
		{
			// 97C0EA724599AD40BF978CBC2BA373B2
			// 14E67C9ABAD9A749D819B14505BC6A64
			// 11D3D2A72448EDC7197ABECC8830F85C

			tag.print("parse AS2 bytes");
			parseActionBytes(ps, br.readRemaining, tag);
		}
	}

	br.finish(tag);
}

void readImport(ref TagParserState ps, ref SwfTag tag)
in (
	tag.code == SwfTagCode.Import || // 57
	tag.code == SwfTagCode.Import2)  // 71
{
	auto br = SwfByteReader(tag.data);

	// slaan.swf      http://127.1.1.1/dbtest.php?do=analyze&md5=3C1B0EF26A250EADAF54759040BE4B7E
	// RollGirlEE.swf http://127.1.1.1/dbtest.php?do=analyze&md5=A3252D7BF286B253AD2FC6576F4D6835

	// XXX: "Import" exists in swf5, might need charset conversion
	// --- collection has no valid SWF5 flashes with the tag

	// xxx: the version check might be for Import2 instead?
	// -- all Import flashes in /f/ + localflashes are SWF7 or below

	const(char)[] url = br.readNullTerminatedUtf8();
	if (ps.reader.swfHeader.swfVersion >= 8)
	{
		br.skip!ushort; // flags
	}
	uint count = br.read!ushort;

	static if (GlobalConfig.OutputStrings)
	{
		if (url.length)
		{
			urlEncodeMin(url, (scope s)
			{
				printf("!import-swf %.*s\n", cast(int)s.length, s.ptr);
			});
		}
	}

	foreach (_; 0..count)
	{
		br.skip!ushort; // objectId
		const(char)[] symbolName = br.readNullTerminatedUtf8();

		static if (GlobalConfig.OutputStrings)
		{
			if (symbolName.length)
			{
				urlEncodeMin(symbolName, (scope s)
				{
					printf("!import-obj %.*s\n", cast(int)s.length, s.ptr);
				});
			}
		}
	}

	br.finish(tag);
}

// https://www.m2osw.com/swf_tag_fileattributes
void readFileAttributes(ref TagParserState ps, ref SwfTag tag)
in (tag.code == SwfTagCode.FileAttributes) // 69
{
	auto br = SwfBitReader(tag.data);
	uint val = br.read!uint;

	if ((val & (1<<3)) && ps.reader.swfHeader.swfVersion < 9)
	{
		// in flash player 10.3.183 and newer, this would exit with:
		// "Warning: Failed to parse corrupt data."
		ps.reader.hardErrors.add(SwfHardError.as3InOldFlash);
		tag.print("AS3 in swf version %d", ps.reader.swfHeader.swfVersion);
	}
}

// https://www.m2osw.com/swf_tag_doabcdefine
// https://www.m2osw.com/swf_tag_doabc
void readDoABC(ref TagParserState ps, ref SwfTag tag)
in (
	tag.code == SwfTagCode.DoABCDefine || // 72
	tag.code == SwfTagCode.DoABC)         // 82
{
	auto br = SwfBitReader(tag.data);

	if (tag.code == SwfTagCode.DoABC)
	{
		br.skipBits(32); // flags
		const(char)[] name = br.readNullTerminatedUtf8();

		static if (GlobalConfig.OutputStrings)
		{
			if (name.length)
			{
				urlEncodeMin(name, (scope s)
				{
					printf("!as3-package %.*s\n", cast(int)s.length, s.ptr);
				});
			}
		}
	}

	uint ver = br.read!uint;
	uint verMinor = ver & 0xffff;
	uint verMajor = ver >> 16;

	if (!(verMinor == 0x10 && verMajor == 0x2e))
	{
		tag.print("unknown AS3 script version: minor=%02x major=%02x", verMinor, verMajor);
		return;
	}

	enum PRINT = 0;

	// ints
	if (uint count = br.readU30())
	{
		count--;
		foreach (_; 0..count)
		{
			uint val = br.readU30();
			if (br.overflow)
			{
				break;
			}
		}
	}

	// uints
	if (uint count = br.readU30())
	{
		count--;
		foreach (_; 0..count)
		{
			uint val = br.readU30();
			if (br.overflow)
			{
				break;
			}
		}
	}

	// doubles
	if (uint count = br.readU30())
	{
		count--;
		br.skipBits(64*count);
	}

	// strings
	if (uint count = br.readU30())
	{
		count--;
		foreach (_; 0..count)
		{
			const(char)[] str = cast(char[])br.readBytesNoCopy(br.readU30());
			if (br.overflow)
			{
				break;
			}
			static if (GlobalConfig.OutputStrings)
			{
				if (str.length && ps.as3StringsSeen.addNew(str))
				{
					urlEncodeMin(str, (scope s)
					{
						printf("!as3-string %.*s\n", cast(int)s.length, s.ptr);
					});
				}
			}
		}
	}

	// there's more stuff but we're not interested
	// https://web.archive.org/web/20220523173435/https://www.m2osw.com/mo_references_view/sswf_docs/abcFormat.html

	br.finishIncomplete(tag);
}

void readSymbolClass(ref SwfTag tag)
in (tag.code == SwfTagCode.SymbolClass) // 76
{
	// http://127.1.1.1/dbtest.php?do=analyze&md5=11273F0EB53DC070489750048C7676B2
	auto br = SwfBitReader(tag.data);

	uint count = br.read!ushort;
	foreach (_; 0..count)
	{
		uint tagId = br.read!ushort;
		const(char)[] className = br.readNullTerminatedUtf8();

		static if (GlobalConfig.OutputStrings)
		{
			if (className.length)
			{
				urlEncodeMin(className, (scope s)
				{
					printf("!class-name %.*s\n", cast(int)s.length, s.ptr);
				});
			}
		}
	}

	br.finish(tag);
}

void readMetadata(ref SwfTag tag)
in (tag.code == SwfTagCode.Metadata) // 77
{
	const(char)[] data = cast(char[])tag.data;

	// (TODO: is this always null-terminated? if it is, should read it as a string instead)
	// also, is this ever anything other than xml?

	if (data.length && data[$-1] == 0)
	{
		// http://127.1.1.1/dbtest.php?do=analyze&md5=A57318BA0C11616BB77E1ACB5040AFCE
		data = data[0..$-1];
	}

	static if (GlobalConfig.OutputStrings)
	{
		if (data.length)
		{
			urlEncodeMin(data, (scope s)
			{
				printf("!metadata %.*s\n", cast(int)s.length, s.ptr);
			});
		}
	}
}

void readDefineSceneAndFrameData(ref SwfTag tag)
in (tag.code == SwfTagCode.DefineSceneAndFrameData) // 86
{
	auto br = SwfBitReader(tag.data);

	// WARNING: ffdec shows a different structure than the docs
	// https://www.m2osw.com/swf_tag_definesceneandframedata
	// not sure what the type of the integers is (U30 seems to work)

	// tests:
	// 1 scene: http://127.1.1.1/dbtest.php?do=analyze&md5=11273F0EB53DC070489750048C7676B2
	// many scenes: http://127.1.1.1/dbtest.php?do=analyze&md5=AE141974B2A871E5562EDD933A82207C
	// non-zero frame labels: http://127.1.1.1/dbtest.php?do=analyze&md5=C4055F156B966DD5688A1CD247A6C0EF

	uint sceneCount = br.readU30();
	foreach (_; 0..sceneCount)
	{
		uint          offset = br.readU30();
		const(char)[] name   = br.readNullTerminatedUtf8();

		static if (GlobalConfig.OutputStrings)
		{
			if (name.length)
			{
				urlEncodeMin(name, (scope s)
				{
					printf("!scene-name %.*s\n", cast(int)s.length, s.ptr);
				});
			}
		}
	}

	uint frameLabelCount = br.readU30();
	foreach (_; 0..frameLabelCount)
	{
		uint          frame = br.readU30();
		const(char)[] name  = br.readNullTerminatedUtf8();

		static if (GlobalConfig.OutputStrings)
		{
			if (name.length)
			{
				urlEncodeMin(name, (scope s)
				{
					printf("!frame-name %.*s\n", cast(int)s.length, s.ptr);
				});
			}
		}
	}

	br.finish(tag);
}

// https://www.m2osw.com/swf_tag_definebinarydata
void readDefineBinaryData(ref SwfTag tag)
in (tag.code == SwfTagCode.DefineBinaryData) // 87
{
	auto br = SwfByteReader(tag.data);

	br.skip!ushort; // data id
	br.skip!uint;   // reserved

	const(ubyte)[] data = br.remaining;

	bool printed;
	if (data.length >= SwfHeader.sizeof)
	{
		auto header = data[0..SwfHeader.sizeof].as!SwfHeader;
		if (header.isValid)
		{
			explainBytes(data, 16, (scope exp)
			{
				printf("!embedded-swf %zu %.*s\n", data.length, cast(int)exp.length, exp.ptr);
			});
			printed = true;
		}
	}
	if (!printed)
	{
		explainBytes(data, 16, (scope exp)
		{
			printf("!embedded-data %zu %.*s\n", data.length, cast(int)exp.length, exp.ptr);
		});
	}

	// might as well try
	parseSoundData(tag.data, tag);
}

void readDefineFontName(ref TagParserState ps, ref SwfTag tag)
in (tag.code == SwfTagCode.DefineFontName) // 88
{
	auto br = SwfBitReader(tag.data);

	uint fontId = br.read!ushort;
	const(char)[] name = br.readNullTerminatedUtf8();
	const(char)[] copyright = br.readNullTerminatedUtf8();

	// utf-8 in SWF4: http://127.1.1.1/dbtest.php?do=analyze&md5=E48A94E648B5D0B3F7F518D3890A917F
	// ^ probably made with a newer version of flash, just exported to target old players

	static if (GlobalConfig.OutputStrings)
	{
		if (name.length && ps.fontNamesSeen.addNew(name))
		{
			urlEncodeMin(name, (scope s)
			{
				printf("!font-name %.*s\n", cast(int)s.length, s.ptr);
			});
		}
		if (copyright.length && ps.fontCopyrightsSeen.addNew(copyright))
		{
			urlEncodeMin(copyright, (scope s)
			{
				printf("!font-copyright %.*s\n", cast(int)s.length, s.ptr);
			});
		}
	}

	br.finish(tag);
}

// -----------------------------------------------------------------------------

void finish(ref SwfBitReader br, ref SwfTag tag)
{
	if (br.overflow)
	{
		tag.print("parsing overflow");
	}
	else if (br.totalBits-br.curBit >= 8)
	{
		const(ubyte)[] remaining = br.remaining;
		explainBytes(remaining, 32, (scope exp)
		{
			tag.print("%zu bytes left after parsing: %.*s",
				remaining.length,
				cast(int)exp.length, exp.ptr);
		});
	}
}

void finish(ref SwfByteReader br, ref SwfTag tag)
{
	if (br.overflow)
	{
		tag.print("parsing overflow");
	}
	else if (br.bytesLeft)
	{
		explainBytes(br.remaining, 32, (scope exp)
		{
			tag.print("%zu bytes left at %08llx: %.*s",
				br.bytesLeft,
				tag.dataPosInFile(br.curByte),
				cast(int)exp.length, exp.ptr);
		});
	}
}

void finishIncomplete(ref SwfBitReader br, ref SwfTag tag)
{
	if (br.overflow)
	{
		tag.print("parsing overflow");
	}
}

void finishIncomplete(ref SwfByteReader br, ref SwfTag tag)
{
	if (br.overflow)
	{
		tag.print("parsing overflow");
	}
}

/**
 * cast byte array to struct
 */
T as(T)(scope const(ubyte)[] data)
if (__traits(getPointerBitmap, T) == [T.sizeof, 0]) // no pointers
{
	assert(data.length == T.sizeof);
	return *cast(T*)data.ptr;
}

/**
 * parses AS2 bytecode which we might get from several tags
 */
void parseActionBytes(ref TagParserState ps, scope const(ubyte)[] data, ref SwfTag tag)
in (
	tag.code == SwfTagCode.DefineButton ||  // 7
	tag.code == SwfTagCode.DoAction ||      // 12
	tag.code == SwfTagCode.PlaceObject2 ||  // 26
	tag.code == SwfTagCode.DefineButton2 || // 34
	tag.code == SwfTagCode.Export ||        // 56 (hack)
	tag.code == SwfTagCode.DoInitAction ||  // 59
	tag.code == SwfTagCode.PlaceObject3)    // 70
{
	auto br = SwfByteReader(data);

	scope addString = (scope const(ubyte)[] strBytes)
	{
		static if (GlobalConfig.OutputStrings)
		{
			if (strBytes.length && ps.as2StringsSeen.addNew(strBytes))
			{
				ps.decodeText(strBytes, tag, (scope str)
				{
					urlEncodeMin(str, (scope s)
					{
						printf("!as2-string %.*s\n", cast(int)s.length, s.ptr);
					});
				});
			}
		}
	};

	// reference:
	// https://github.com/ruffle-rs/ruffle/blob/master/swf/src/avm1/opcode.rs
	// https://github.com/ruffle-rs/ruffle/blob/master/swf/src/avm1/read.rs

	// popularity numbers from 2000 flashes:
	// 0x96 Push               3001591
	// 0x00 End                137223 <----
	// 0x88 ConstantPool       64157
	// 0x8e DefineFunction2    31514
	// 0x9b DefineFunction     14039
	// 0x8c GotoLabel          8734
	// 0x8b SetTarget          6482
	// 0x83 GetUrl             1552
	// 0x8f Try                92

	// < 0x80 --> 4319074
	// -> End  -> 137223
	// -> rest -> 4181851

	// >= 0x80 ---> 3581163
	// -> parsed -> 3128161
	// -> rest   -> 453002

	static immutable char*[0x9f+1] knownOpcodeNames = [
		0x00: "End",

		0x04: "NextFrame",
		0x05: "PreviousFrame",
		0x06: "Play",
		0x07: "Stop",
		0x08: "ToggleQuality",
		0x09: "StopSounds",
		0x0A: "Add",
		0x0B: "Subtract",
		0x0C: "Multiply",
		0x0D: "Divide",
		0x0E: "Equals",
		0x0F: "Less",
		0x10: "And",
		0x11: "Or",
		0x12: "Not",
		0x13: "StringEquals",
		0x14: "StringLength",
		0x15: "StringExtract",

		0x17: "Pop",
		0x18: "ToInteger",

		0x1C: "GetVariable",
		0x1D: "SetVariable",

		0x20: "SetTarget2",
		0x21: "StringAdd",
		0x22: "GetProperty",
		0x23: "SetProperty",
		0x24: "CloneSprite",
		0x25: "RemoveSprite",
		0x26: "Trace",
		0x27: "StartDrag",
		0x28: "EndDrag",
		0x29: "StringLess",
		0x2A: "Throw",
		0x2B: "CastOp",
		0x2C: "ImplementsOp",

		0x30: "RandomNumber",
		0x31: "MBStringLength",
		0x32: "CharToAscii",
		0x33: "AsciiToChar",
		0x34: "GetTime",
		0x35: "MBStringExtract",
		0x36: "MBCharToAscii",
		0x37: "MBAsciiToChar",

		0x3A: "Delete",
		0x3B: "Delete2",
		0x3C: "DefineLocal",
		0x3D: "CallFunction",
		0x3E: "Return",
		0x3F: "Modulo",
		0x40: "NewObject",
		0x41: "DefineLocal2",
		0x42: "InitArray",
		0x43: "InitObject",
		0x44: "TypeOf",
		0x45: "TargetPath",
		0x46: "Enumerate",
		0x47: "Add2",
		0x48: "Less2",
		0x49: "Equals2",
		0x4A: "ToNumber",
		0x4B: "ToString",
		0x4C: "PushDuplicate",
		0x4D: "StackSwap",
		0x4E: "GetMember",
		0x4F: "SetMember",
		0x50: "Increment",
		0x51: "Decrement",
		0x52: "CallMethod",
		0x53: "NewMethod",
		0x54: "InstanceOf",
		0x55: "Enumerate2",

		0x60: "BitAnd",
		0x61: "BitOr",
		0x62: "BitXor",
		0x63: "BitLShift",
		0x64: "BitRShift",
		0x65: "BitURShift",
		0x66: "StrictEquals",
		0x67: "Greater",
		0x68: "StringGreater",
		0x69: "Extends",

		0x81: "GotoFrame",

		0x83: "GetUrl",

		0x87: "StoreRegister",
		0x88: "ConstantPool",

		0x8A: "WaitForFrame",
		0x8B: "SetTarget",
		0x8C: "GotoLabel",
		0x8D: "WaitForFrame2",
		0x8E: "DefineFunction2",
		0x8F: "Try",

		0x94: "With",

		0x96: "Push",

		0x99: "Jump",
		0x9A: "GetUrl2",
		0x9B: "DefineFunction",
		0x9D: "If",
		0x9E: "Call",
		0x9F: "GotoFrame2",
	];

	bool seenEnd;
	while (!br.empty)
	{
		uint opcode = br.read!ubyte;

		if (0)
		{
			const(char)* name = (opcode < knownOpcodeNames.length) ? knownOpcodeNames[opcode] : null;
			char[32] tmp = void;
			if (!name)
			{
				snprintf(tmp.ptr, tmp.length, "Unknown 0x%02x", opcode);
				name = tmp.ptr;
			}
			tag.print("%08zx: %s", br.curByte-1, name);
		}

		if (opcode < 0x80)
		{
			if (opcode != 0)
			{
				if (opcode == 0x5f || opcode == 0x89)
				{
					tag.print("AS2 undocumented opcode 0x%02hhx", opcode);
				}
				continue;
			}
			seenEnd = true;
			if (!br.empty)
			{
				// legal and ok
				tag.print("AS2 end reached with %zu bytes left to read", br.bytesLeft);
			}
			break;
		}

		uint size = br.read!ushort;
		const(ubyte)[] opData = br.readBytesNoCopy(size);
		if (br.overflow)
		{
			// 1. overflow reading size: fatal since 11_2
			// 2. overflow reading data: fatal since 10_3
			tag.print("AS2 opcode data overflow (op=0x%02hhx size=%u)", opcode, size);
			return;
		}

		if (opcode == 0x96) // Push
		{
			static immutable uint[10] typeSizes = [
				0: 0,             // null-terminated string (read manually)
				1: float.sizeof,  // 32-bit float
				2: 0,             // null (no data)
				3: 0,             // undefined (no data)
				4: ubyte.sizeof,  // 8-bit register number
				5: ubyte.sizeof,  // boolean (8 bits!)
				6: double.sizeof, // 64-bit double
				7: int.sizeof,    // 32-bit int
				8: ubyte.sizeof,  // 8-bit constant pool index
				9: ushort.sizeof, // 16-bit constant pool index
			];
			// note: in flash player, read values are allowed to overflow the opcode's data
			// they just use data from the rest of the script buffer in that case
			// for strings, the null terminator can be anywhere in the script buffer
			// however, if the read would overflow the [script buffer or tag data it's from?], the value pushed is 0/empty/undefined depending on type
			auto opRead = SwfByteReader(opData);
			while (!opRead.empty)
			{
				uint type = opRead.read!ubyte;
				if (type != 0 && type < typeSizes.length)
				{
					opRead.skipBytes(typeSizes[type]);
				}
				else if (type == 0)
				{
					addString(opRead.readNullTerminatedBytes());
				}
				else
				{
					// fatal since 10_3
					// keep going to match old flash player t. ruffle
					tag.print("AS2 unknown pushed type %u", type);
				}
			}
			if (opRead.overflow)
			{
				// allowed
				tag.print("AS2 overflow parsing push opcode");
			}
		}
		else if (opcode == 0x88) // ConstantPool
		{
			auto opRead = SwfByteReader(opData);

			uint count = opRead.read!ushort;
			uint parsedCount;

			// count higher than actual number of strings: fatal since 9_0r151_0
			// unterminated string: fatal since 9_0r151_0
			// extra data: allowed

			foreach (_; 0..count)
			{
				const(ubyte)[] strBytes = opRead.readNullTerminatedBytes();
				if (opRead.overflow)
				{
					break;
				}
				addString(strBytes);
				parsedCount++;
				if (opRead.empty)
				{
					break;
				}
			}

			if (!opRead.empty)
			{
				tag.print("AS2 constant pool ended with %zu bytes left", opRead.bytesLeft);
			}
			else if (opRead.overflow)
			{
				tag.print("AS2 overflow parsing constant pool");
			}
		}
		else if (
			opcode == 0x8e || // DefineFunction2
			opcode == 0x9b || // DefineFunction
			opcode == 0x8c || // GotoLabel
			opcode == 0x8b)   // SetTarget
		{
			auto opRead = SwfByteReader(opData);
			addString(opRead.readNullTerminatedBytes());
		}
		else if (opcode == 0x83) // GetUrl
		{
			// http://127.1.1.1/dbtest.php?do=analyze&md5=B25678AF33D1A1BA147C8FC152F43BBF
			auto opRead = SwfByteReader(opData);
			addString(opRead.readNullTerminatedBytes()); // url
			addString(opRead.readNullTerminatedBytes()); // target
		}
		else if (opcode == 0x8f) // Try
		{
			auto opRead = SwfByteReader(opData);
			uint flags = opRead.read!ubyte;
			if (flags & (1<<2))
			{
				opRead.skipBytes(ushort.sizeof*3);
				addString(opRead.readNullTerminatedBytes()); // catchVar
			}
		}
	}

	if (br.overflow)
	{
		tag.print("AS2 parsing overflow");
	}
	else if (!seenEnd)
	{
		// allowed
		tag.print("AS2 missing end opcode");
	}
}

// https://www.m2osw.com/swf_struct_button
void parseSwfButtons(ref SwfBitReader br, ref TagParserState ps, ref SwfTag tag)
in (
	tag.code == SwfTagCode.DefineButton || // 7
	tag.code == SwfTagCode.DefineButton2)  // 34
{
	enum BlendMode  = 1<<5;
	enum FilterList = 1<<4;

	for (;;)
	{
		uint states = br.read!ubyte;

		if (states == 0)
		{
			break;
		}

		br.skipBits(32); // idRef, layer
		SwfMatrix.skip(br);

		if (tag.code == SwfTagCode.DefineButton2)
		{
			SwfColorTransform.skipWithAlpha(br, tag);
		}

		if (
			(states & (FilterList|BlendMode)) != 0 &&
			ps.reader.swfHeader.swfVersion >= 8)
		{
			if ((states & FilterList) != 0)
			{
				uint filterCount = br.read!ubyte;
				// 2: http://127.1.1.1/dbtest.php?do=analyze&md5=F7370DCFC411EB665081FE897CA5A03E
				foreach (_; 0..filterCount)
				{
					SwfAnyFilter.skip(br, tag);
				}
			}
			if ((states & BlendMode) != 0)
			{
				br.skipBits(8); // blendMode
			}
		}
	}
}

void parseSoundData(const(ubyte)[] soundData, ref SwfTag tag)
{
	// https://en.wikipedia.org/wiki/ID3#ID3v1_and_ID3v1.1[5]
	static struct ID3v1
	{
	align(1):
		char[3] header;
		char[30] title;
		char[30] artist;
		char[30] album;
		char[4] year;
		union
		{
			struct
			{
				char[30] comment30;
			}
			struct
			{
				char[28] comment28;
				ubyte zerobyte;
				ubyte track;
			}
		}
		ubyte genre;
		char[] comment() return
		{
			// wikipedia: if a track number is stored [and the comment is 28 bytes
			//  instead of 30], zerobyte contains a binary 0
			if (zerobyte == 0)
				return comment28;
			else
				return comment30;
		}
	}
	static assert(ID3v1.sizeof == 128);

	char[] trimToLength(char[] str)
	{
		// wikipedia: fields are padded with \0 or spaces
		while (str.length && str[$-1] <= ' ')
		{
			str = str[0..$-1];
		}
		return str;
	}

	if (soundData.length >= 128 && soundData[$-128..$-128+3] == "TAG")
	{
		auto id3 = cast(ID3v1*)soundData[$-128..$].ptr;
		auto title = trimToLength(id3.title);
		if (title.length)
		{
			urlEncodeMin(title, (scope s)
			{
				printf("!id3-title %.*s\n", cast(int)s.length, s.ptr);
			});
		}
		auto artist = trimToLength(id3.artist);
		if (artist.length)
		{
			urlEncodeMin(artist, (scope s)
			{
				printf("!id3-artist %.*s\n", cast(int)s.length, s.ptr);
			});
		}
		auto album = trimToLength(id3.album);
		if (album.length)
		{
			urlEncodeMin(album, (scope s)
			{
				printf("!id3-album %.*s\n", cast(int)s.length, s.ptr);
			});
		}
		auto comment = trimToLength(id3.comment);
		if (comment.length)
		{
			urlEncodeMin(comment, (scope s)
			{
				printf("!id3-comment %.*s\n", cast(int)s.length, s.ptr);
			});
		}
	}

	bool hasStringAtOffset(const(ubyte)[] buf, size_t pos, string str)
	{
		if (pos <= buf.length && buf.length-pos >= str.length)
			return buf[pos..pos+str.length] == str;
		else
			return false;
	}

	if (hasStringAtOffset(soundData, 0, "ID3"))
	{
		tag.print("found id3 at +0 bytes (fixme)");
	}

	if (hasStringAtOffset(soundData, 2, "ID3"))
	{
		// d427cf5c404c387582b36389d3e50adc
		// miotest
		tag.print("found id3 at +2 bytes (fixme)");
	}

	// wikipedia: enhanced TAG+ is 227 bytes and comes before ID3v1
	if (hasStringAtOffset(soundData, soundData.length-(128+227), "TAG+"))
	{
		tag.print("found id3 enhanced tag (fixme)");
	}

	// http://fileformats.archiveteam.org/wiki/ID3
	if (hasStringAtOffset(soundData, soundData.length-(138), "3DI"))
	{
		tag.print("found id3 3DI tag at 138 bytes (fixme)");
	}

	// http://fileformats.archiveteam.org/wiki/ID3
	if (hasStringAtOffset(soundData, soundData.length-(10), "3DI"))
	{
		tag.print("found id3 3DI tag at 10 bytes (fixme)");
	}
}
