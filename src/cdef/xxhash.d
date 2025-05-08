module swfbiganal.cdef.xxhash;

alias XXH32_hash_t = uint;
alias XXH64_hash_t = ulong;

extern(C) XXH32_hash_t XXH32(
	scope const(void)* input,
	size_t             length,
	XXH32_hash_t       seed);

extern(C) XXH64_hash_t XXH64(
	scope const(void)* input,
	size_t             length,
	XXH64_hash_t       seed);

extern(C) XXH64_hash_t XXH3_64bits(
	scope const(void)* data,
	size_t             len);
