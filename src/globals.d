module swfbiganal.globals;

struct GlobalConfig
{
	/** output a line for each tag (main.d) */
	__gshared bool OutputTags = false;

	enum ParseTags = 1;

	/** collect and print all strings inside the flash (tags.d) */
	enum OutputStrings = 1;

	// sizes of buffers used for reading/decompressing data
	enum size_t ReadBufferSize = 128*1024;
	enum size_t DecompressBufferSize = 2*128*1024;
}
