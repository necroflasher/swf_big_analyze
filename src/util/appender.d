module swfbiganal.util.appender;

import core.stdc.stdlib;
import core.stdc.string;
import swfbiganal.util.compiler;

/**
 * Simplified version of D's Appender.
 */
private struct Appender(A : E[], E, M)
if (__traits(isIntegral, E))
{
	private E*     data;
	private size_t length;
	private size_t capacity;

	invariant
	{
		assert(length <= capacity);
		if (length)
		{
			assert(data != null);
		}
	}

	public inout(E)[] opSlice() inout
	{
		return data[0..length];
	}

	public void opOpAssign(string op : "~")(E val)
	{
		reserve(1);
		data[length] = val;
		length += 1;
	}

	public void opOpAssign(string op : "~")(scope const(E)[] val)
	{
		reserve(val.length);
		memcpy(&data[length], val.ptr, val.length*E.sizeof);
		length += val.length;
	}

	// https://dlang.org/library/std/array/appender.reserve.html
	public void reserve(size_t numElements)
	{
		if (expect(capacity-length < numElements, false))
		{
			setCapacity(length+numElements);
			assert(capacity-length >= numElements);
		}
	}

	public void clear()
	{
		length = 0;
	}

	public void shrinkTo(size_t wantCapacity)
	{
		// note: do not realloc here, OG doesn't either and it's slow
		if (length > wantCapacity)
		{
			length = wantCapacity;
		}
	}

	private void setCapacity(size_t newCapacity)
	{
		capacity = (newCapacity|0x3ff)+1;

		data = cast(E*)M.realloc(data, capacity*E.sizeof);

		if (expect(!data, false))
			assert(0, "out of memory");
	}
}

/**
 * Like Appender, but uses malloc/free and frees the allocation when the struct
 * goes out of scope.
 */
public struct ScopedAppender(A : E[], E)
if (__traits(isIntegral, E))
{
	private alias M = LibcMemory;

	public Appender!(E[], E, M) ap;
	public alias ap this; // old syntax for old gdc

	@disable this(this);

	public ~this()
	{
		M.free(ap.data);
		ap.data = null;
	}
}

unittest
{
	ScopedAppender!(char[]) ap;
	assert(ap[] == "");
	ap ~= "";
	assert(ap[] == "");
	ap ~= 'a';
	assert(ap[] == "a");
	ap ~= "ss";
	assert(ap[] == "ass");
	ap ~= "";
	assert(ap[] == "ass");

	assert(__traits(compiles, { ScopedAppender!(int[]) zap; }));
	assert(!__traits(compiles, { ScopedAppender!(void*[]) zap; }));

	// does not compile
	//assert(__traits(compiles, { Appender!string zap; }));
}

private:

struct LibcMemory
{
	alias realloc = core.stdc.stdlib.realloc;
	alias free = core.stdc.stdlib.free;
}
