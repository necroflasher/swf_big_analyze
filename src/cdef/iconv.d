module swfbiganal.cdef.iconv;

import core.stdc.config;

alias iconv_t = c_ulong;

extern(C) iconv_t iconv_open(
	const(char)* tocode,
	const(char)* fromcode);

extern(C) size_t iconv(
	iconv_t       cd,
	const(void)** inbuf,
	size_t*       inbytesleft,
	void**        outbuf,
	size_t*       outbytesleft);

extern(C) int iconv_close(iconv_t cd);
