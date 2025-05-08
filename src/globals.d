module swfbiganal.globals;

/**
 * charset to use for decoding non-unicode text in old flashes (SWF1-5)
 * 
 * this depends on the locale of the machine the flash was created on, more
 * specifically the ANSI code page
 * 
 * the value should probably be one of the following:
 * - "Windows-1250" (Latin-2; Central European)
 * - "Windows-1251" (Cyrillic)
 * - "Windows-1252" (Latin-1; Western European)
 * - "Windows-1253" (Greek)
 * - "Windows-1254" (Turkish)
 * - "Windows-1255" (Hebrew)
 * - "Windows-1256" (Arabic)
 * - "Windows-1257" (Baltic)
 * - "Windows-1258" (Vietnamese)
 * - "CP874" (Thai)
 * - "CP932" (Shift JIS; Japanese)
 * - "CP936" (GBK; Simplified Chinese)
 * - "CP949" (Unified Hangul Code; Korean)
 * - "CP950" (Big5; Traditional Chinese)
 * 
 * source:
 * - https://stackoverflow.com/a/66002312
 * - https://en.wikipedia.org/wiki/Windows_code_page
 */
__gshared const(char)* g_charset;

/**
 * full path to the swf file currently being parsed
 */
__gshared const(char)* g_swfFilePath;

struct GlobalConfig
{
	/** output a line for each tag (main.d) */
	__gshared bool OutputTags = false;

	enum ParseTags = 1;

	/** collect and print all strings inside the flash (tags.d) */
	enum OutputStrings = 1;
}
