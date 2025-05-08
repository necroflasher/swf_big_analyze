module swfbiganal.util.compiler;

// TODO: expect returns int on gdc, fix the dmd one to follow

version(GNU)
{
	public import gcc.attributes : cold;
	public import gcc.builtins : expect = __builtin_expect;
}
else version(LDC)
{
	public import ldc.attributes : cold;
	public import ldc.intrinsics : expect = llvm_expect;
}
else
{
	struct cold {}

	// https://github.com/ldc-developers/druntime/blob/ldc/src/ldc/intrinsics.di
	auto ref T expect(T)(auto ref T val, auto ref T expectedVal)
	if (__traits(isIntegral, T))
	{
		pragma(inline, true);
		return val;
	}
}

unittest
{
	int i;
	bool fn()
	{
		i++;
		return true;
	}
	if (expect(fn(), true))
		assert(i == 1);
	else
		assert(0);
}
