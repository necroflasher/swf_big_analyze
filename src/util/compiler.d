module swfbiganal.util.compiler;

version (GNU)
{
	public import gcc.attributes : cold;
	public import gcc.builtins : expect = __builtin_expect;
	// type: extern (C) c_long function(c_long, c_long) pure nothrow @nogc @safe
}
else version (LDC)
{
	public import ldc.attributes : cold;
	public import ldc.intrinsics : expect = llvm_expect;
	// https://github.com/ldc-developers/druntime/blob/ldc/src/ldc/intrinsics.di
	// type: T llvm_expect(T)(T val, T expectedVal) if (__traits(isIntegral, T));
}
else
{
	import core.stdc.config : c_long;

	struct cold {}

	c_long expect(c_long val, c_long expectedVal) pure nothrow @nogc @safe
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
