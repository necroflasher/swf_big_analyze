module swfbiganal.swftypes.swftag;

import core.stdc.stdarg;
import core.stdc.stdio;
import swfbiganal.util.compiler;

struct SwfTag
{
	uint           code;
	const(ubyte)[] data;
	bool           longFormat;
	ulong          fileOffset; // position of this tag's first byte in the swf data

	ulong dataPosInFile(size_t offset = 0) const pure
	{
		ulong rv = fileOffset;
		rv += 2; // ushort code+size
		if (longFormat)
			rv += 4; // uint longSize
		rv += offset;
		return rv;
	}

	const(char)* name() const pure
	{
		return SwfTag.name(code);
	}

	static const(char)* name(uint code) pure
	{
		return getString(swfTagKnownNames, code, "unknown");
	}
}

private const(char)* getString(size_t length)(ref const char*[length] arr, size_t idx, const(char)* fallback = null)
{
	if (idx < length)
	{
		if (const(char)* s = arr[idx])
			return s;
	}
	return fallback;
}

@cold
void print(ref inout(SwfTag) tag, string str)
{
	pragma(inline, false);
	printf("#! %08llx %s<%u>: %.*s\n", tag.fileOffset, tag.name, tag.code, cast(int)str.length, str.ptr);
}

@cold
extern(C)
pragma(printf)
void print(ref inout(SwfTag) tag, const(char)* fmt, ...)
{
	pragma(inline, false);
	va_list ap;
	va_start(ap, fmt);
	printf("#! %08llx %s<%u>: ", tag.fileOffset, tag.name, tag.code);
	vprintf(fmt, ap);
	printf("\n");
	va_end(ap);
}

// highest possible tag code that can appear in a .swf file
// they're encoded with 10 bits, so this is the max value of that many bits
enum SwfHighestPossibleTagCode = 0b_11111_11111;

// total number of possible tag codes that can appear in a .swf file
enum SwfTotalPossibleTagCodes = SwfHighestPossibleTagCode+1;

enum SwfTagCode
{
	// flash 1
	End = 0,
	ShowFrame = 1,
	DefineShape = 2,
	FreeCharacter = 3,
	PlaceObject = 4,
	RemoveObject = 5,
	DefineBitsJPEG = 6,
	DefineButton = 7,
	JPEGTables = 8,
	SetBackgroundColor = 9,
	DefineFont = 10,
	DefineText = 11,
	DoAction = 12,
	DefineFontInfo = 13,

	// flash 2 (14-)
	DefineSound = 14,
	StartSound = 15,
	// 16 - StopSound?
	DefineButtonSound = 17,
	SoundStreamHead = 18,
	SoundStreamBlock = 19,
	DefineBitsLossless = 20,
	DefineBitsJPEG2 = 21,
	DefineShape2 = 22,
	// 23 - DefineButtonCxform?
	Protect = 24,

	// flash 3 (25-)
	PathsArePostscript = 25,
	PlaceObject2 = 26,
	// 27 - unknown
	RemoveObject2 = 28,
	// 29 - SyncFrame?
	// 30 - unknown
	// 31 - FreeAll?
	DefineShape3 = 32,
	DefineText2 = 33,
	DefineButton2 = 34,
	DefineBitsJPEG3 = 35,
	DefineBitsLossless2 = 36,
	DefineEditText = 37,
	// 38 - DefineVideo?
	DefineSprite = 39,
	NameCharacter = 40,
	ProductInfo = 41,
	// 42 - DefineTextFormat?
	FrameLabel = 43,
	// 44 - unknown
	SoundStreamHead2 = 45,
	DefineMorphShape = 46,
	// 47 - GenerateFrame?
	DefineFont2 = 48,
	// 49 - GeneratorCommand?
	// 50 - DefineCommandObject?
	// 51 - CharacterSet?
	// 52 - ExternalFont?
	// 53 - unknown
	// 54 - unknown
	// 55 - unknown

	// flash 5 (50-)
	Export = 56,
	Import = 57,
	EnableDebugger = 58,

	// flash 6 (59-)
	DoInitAction = 59,
	DefineVideoStream = 60,
	VideoFrame = 61,
	DefineFontInfo2 = 62,
	DebugID = 63,
	EnableDebugger2 = 64,

	// flash 7 (65-)
	ScriptLimits = 65,
	SetTabIndex = 66,
	// 67 - unknown
	// 68 - unknown

	// flash 8 (69-)
	FileAttributes = 69,
	PlaceObject3 = 70,
	Import2 = 71,
	DoABCDefine = 72,
	DefineFontAlignZones = 73,
	CSMTextSettings = 74,
	DefineFont3 = 75,
	SymbolClass = 76,
	Metadata = 77,
	DefineScalingGrid = 78,
	// 79 - unknown
	// 80 - unknown
	// 81 - unknown
	DoABC = 82,
	DefineShape4 = 83,
	DefineMorphShape2 = 84,
	// 85 - unknown

	// flash 9 (86-)
	DefineSceneAndFrameData = 86,
	DefineBinaryData = 87,
	DefineFontName = 88,
	// 89 - unknown -- something related to sound
	// 90 - DefineBitsJPEG4?

	// flash 10
	DefineFont4 = 91,
	// 92 - unknown
	EnableTelemetry = 93,
	//PlaceObject4 = 94, // RE
	// 254
	// 1022 -> 14? -- could be related to how it sometimes stores the entire tag header?

	// https://github.com/claus/as3swf/tree/master/src/com/codeazur/as3swf/tags/etc
	SWFEncryptActions = 253,
	SWFEncryptSignature = 255,
}

private static immutable char*[256] swfTagKnownNames = [
	0:   "End",
	1:   "ShowFrame",
	2:   "DefineShape",
	3:   "FreeCharacter",
	4:   "PlaceObject",
	5:   "RemoveObject",
	6:   "DefineBitsJPEG",
	7:   "DefineButton",
	8:   "JPEGTables",
	9:   "SetBackgroundColor",
	10:  "DefineFont",
	11:  "DefineText",
	12:  "DoAction",
	13:  "DefineFontInfo",
	14:  "DefineSound",
	15:  "StartSound",
	17:  "DefineButtonSound",
	18:  "SoundStreamHead",
	19:  "SoundStreamBlock",
	20:  "DefineBitsLossless",
	21:  "DefineBitsJPEG2",
	22:  "DefineShape2",
	24:  "Protect",
	25:  "PathsArePostscript",
	26:  "PlaceObject2",
	28:  "RemoveObject2",
	32:  "DefineShape3",
	33:  "DefineText2",
	34:  "DefineButton2",
	35:  "DefineBitsJPEG3",
	36:  "DefineBitsLossless2",
	37:  "DefineEditText",
	39:  "DefineSprite",
	40:  "NameCharacter",
	41:  "ProductInfo",
	43:  "FrameLabel",
	45:  "SoundStreamHead2",
	46:  "DefineMorphShape",
	48:  "DefineFont2",
	56:  "Export",
	57:  "Import",
	58:  "EnableDebugger",
	59:  "DoInitAction",
	60:  "DefineVideoStream",
	61:  "VideoFrame",
	62:  "DefineFontInfo2",
	63:  "DebugID",
	64:  "EnableDebugger2",
	65:  "ScriptLimits",
	66:  "SetTabIndex",
	69:  "FileAttributes",
	70:  "PlaceObject3",
	71:  "Import2",
	72:  "DoABCDefine",
	73:  "DefineFontAlignZones",
	74:  "CSMTextSettings",
	75:  "DefineFont3",
	76:  "SymbolClass",
	77:  "Metadata",
	78:  "DefineScalingGrid",
	82:  "DoABC",
	83:  "DefineShape4",
	84:  "DefineMorphShape2",
	86:  "DefineSceneAndFrameData",
	87:  "DefineBinaryData",
	88:  "DefineFontName",
	91:  "DefineFont4",
	93:  "EnableTelemetry",
	253: "SWFEncryptActions",
	255: "SWFEncryptSignature",
];

unittest
{
	enum
	{
		HasEnum = 1,
		HasName = 2,
	}
	ubyte[SwfTotalPossibleTagCodes] flags;

	foreach (name; __traits(allMembers, SwfTagCode))
	{
		flags[__traits(getMember, SwfTagCode, name)] |= HasEnum;
	}

	foreach (uint code, name; swfTagKnownNames)
	{
		if (name !is null)
		{
			flags[code] |= HasName;
		}
	}

	bool ok = true;
	foreach (uint code, flag; flags)
	{
		if (flag != 0 && flag != (HasEnum|HasName))
		{
			ok = false;
			printf("*** tag %u: HasEnum=%d HasName=%d\n",
				code,
				!!(flag & HasEnum),
				!!(flag & HasName));
		}
	}
	if (!ok)
	{
		assert(0);
	}
}
