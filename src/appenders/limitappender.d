module swfbiganal.appenders.limitappender;

import swfbiganal.util.appender;

struct LimitAppender2(size_t buflen)
{
	ubyte[buflen] data = void;
	size_t        length;
	size_t        limit;

	invariant(limit <= buflen && length <= limit);

	void appendFromRef(ref const(ubyte)[] buf)
	in (isValid)
	{
		size_t want = (limit - length);
		size_t have = buf.length;
		size_t copy = min(want, have);
		data[length..length+copy] = buf[0..copy];
		length += copy;
		buf = buf[copy..$];
	}

	private bool isValid()
	{
		return (limit != 0);
	}

	bool isFull()
	in (isValid)
	{
		return length == limit;
	}

	const(ubyte)[] opSlice()
	in (isValid)
	{
		return data[0..length];
	}

	ubyte* ptr()
	in (isValid)
	{
		return data.ptr;
	}

	void reset()
	in (isValid)
	{
		length = 0;
		limit = 0;
	}

	void opAssign(scope const(ubyte)[] val)
	in (isValid)
	{
		if (val.length <= limit)
		{
			length = val.length;
			data[0..val.length] = val;
		}
		else
		{
			debug
			{
				import core.stdc.stdio;
				fprintf(stderr, "val.length=%zu\n", val.length);
				fprintf(stderr, "limit=%zu\n", limit);
			}
			assert(0);
		}
	}

	const(ubyte)[] opSlice(size_t start, size_t end)
	in (isValid)
	{
		return (this[])[start..end];
	}

	ubyte opIndex(size_t i)
	in (isValid)
	{
		return (this[])[i];
	}
}

private:

auto min(A, B)(A a, B b)
if (is(A == B))
{
	if (b < a) a = b;
	return a;
}

/*unittest
{
	import std.string : representation; // grep: unittest

	LimitAppender la;
	const(ubyte)[] data = "hello".representation;
	const(ubyte)[] tmp;

	// test isValid, isFull, reset
	assert(!la.isValid);
	la = LimitAppender(1);
	assert(la.isValid);
	assert(!la.isFull);
	la.reset();
	assert(!la.isValid);

	// reset keeps the appender allocation
	la = LimitAppender(2);
	tmp = "hi".representation;
	la.appendFromRef(tmp);
	assert(la[].length == 2);
	assert(la[].ptr != null);
	la.reset();
	// access private to skip precondition
	assert(la.ap[].length == 0);
	assert(la.ap[].ptr != null);

	// test append length=5 into limit=4
	tmp = data;
	la = LimitAppender(4);
	la.appendFromRef(tmp);
	assert(la[] == "hell");
	assert(la.isFull);
	assert(tmp == "o");

	// test append length=5 into limit=5
	tmp = data;
	la = LimitAppender(5);
	la.appendFromRef(tmp);
	assert(la[] == "hello");
	assert(la.isFull);
	assert(tmp.ptr != null && tmp.length == 0);

	// test append length=5 into limit=6
	tmp = data;
	la = LimitAppender(6);
	la.appendFromRef(tmp);
	assert(la[] == "hello");
	assert(!la.isFull);
	assert(tmp.ptr != null && tmp.length == 0);
	
	// test append length=0 into limit=1
	tmp = data[0..0];
	la = LimitAppender(1);
	la.appendFromRef(tmp);
	assert(la[].ptr == null); // wasn't allocated
	assert(!la.isFull);
	assert(tmp.ptr != null && tmp.length == 0);
}*/
