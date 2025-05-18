/**
 * based on:
 * https://github.com/rtbo/squiz-box/blob/main/src/squiz_box/c/lzma.d
 */
module swfbiganal.cdef.lzma;

enum lzma_reserved_enum
{
	LZMA_RESERVED_ENUM = 0,
}

enum lzma_ret
{
	OK                = 0,
	STREAM_END        = 1,
	NO_CHECK          = 2,
	UNSUPPORTED_CHECK = 3,
	GET_CHECK         = 4,
	MEM_ERROR         = 5,
	MEMLIMIT_ERROR    = 6,
	FORMAT_ERROR      = 7,
	OPTIONS_ERROR     = 8,
	DATA_ERROR        = 9,
	BUF_ERROR         = 10,
	PROG_ERROR        = 11,
}

enum lzma_action
{
	RUN          = 0,
	SYNC_FLUSH   = 1,
	FULL_FLUSH   = 2,
	FINISH       = 3,
	FULL_BARRIER = 4,
}

struct lzma_allocator;
struct lzma_internal;

struct lzma_stream
{
	const(ubyte)*          next_in;
	size_t                 avail_in;
	ulong                  total_in;

	ubyte*                 next_out;
	size_t                 avail_out;
	ulong                  total_out;

	const(lzma_allocator)* allocator;

	lzma_internal*         internal;

	void*                  reserved_ptr1;
	void*                  reserved_ptr2;
	void*                  reserved_ptr3;
	void*                  reserved_ptr4;
	ulong                  reserved_int1;
	ulong                  reserved_int2;
	size_t                 reserved_int3;
	size_t                 reserved_int4;
	lzma_reserved_enum     reserved_enum1;
	lzma_reserved_enum     reserved_enum2;
}

extern(C) lzma_ret lzma_alone_decoder(
	lzma_stream* strm,
	ulong        memlimit);

extern(C) lzma_ret lzma_code(
	lzma_stream* strm,
	lzma_action  action);

extern(C) void lzma_end(lzma_stream* strm);

// /usr/include/lzma/lzma12.h
enum lzma_mode
{
	LZMA_MODE_FAST = 1,
	LZMA_MODE_NORMAL = 2,
}

// /usr/include/lzma/lzma12.h
enum lzma_match_finder
{
	LZMA_MF_HC3 = 0x03,
	LZMA_MF_HC4 = 0x04,
	LZMA_MF_BT2 = 0x12,
	LZMA_MF_BT3 = 0x13,
	LZMA_MF_BT4 = 0x14,
}

// /usr/include/lzma/lzma12.h
struct lzma_options_lzma
{
	uint dict_size;
	const(ubyte)* preset_dict;
	uint preset_dict_size;
	uint lc;
	uint lp;
	uint pb;
	lzma_mode mode = cast(lzma_mode)0; // zero init
	uint nice_len;
	lzma_match_finder mf = cast(lzma_match_finder)0; // zero init
	uint depth;
	uint ext_flags;
	uint ext_size_low;
	uint ext_size_high;

	uint reserved_int4;
	uint reserved_int5;
	uint reserved_int6;
	uint reserved_int7;
	uint reserved_int8;
	lzma_reserved_enum reserved_enum1;
	lzma_reserved_enum reserved_enum2;
	lzma_reserved_enum reserved_enum3;
	lzma_reserved_enum reserved_enum4;
	void* reserved_ptr1;
	void* reserved_ptr2;
}
enum uint LZMA_DICT_SIZE_MIN = 4096;
enum uint LZMA_DICT_SIZE_DEFAULT = 1<<23;
enum uint LZMA_LCLP_MIN = 0;
enum uint LZMA_LCLP_MAX = 4;
enum uint LZMA_LC_DEFAULT = 3;
enum uint LZMA_LP_DEFAULT = 0;
enum uint LZMA_PB_MIN = 0;
enum uint LZMA_PB_MAX = 4;
enum uint LZMA_PB_DEFAULT = 2;
enum uint LZMA_LZMA1EXT_ALLOW_EOPM = 0x01;

// /usr/include/lzma/lzma12.h
extern(C) lzma_bool lzma_lzma_preset(
	lzma_options_lzma* options,
	uint               preset);

// /usr/include/lzma/container.h
extern(C) lzma_ret lzma_alone_encoder(
	lzma_stream*              strm,
	const(lzma_options_lzma)* options);

// /usr/include/lzma/base.h
alias lzma_bool = ubyte;
