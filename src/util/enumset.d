module swfbiganal.util.enumset;

// VERY simple struct to make a bit field out of an enum
// doesn't support:
// - enums with negative minimum
// - enums with arbitrarily high maximum
// - size optimization for gaps in values
public struct EnumSet(E)
{
	static assert(E.min >= 0);
	static assert(E.max <= 63);

	private ulong val = 0;

	public bool has(E e)
	{
		return !!(val & (ulong(1)<<e));
	}

	public bool add(E e)
	{
		bool had = has(e);
		val |= ulong(1)<<e;
		return had;
	}

	public void remove(E e)
	{
		val &= ~(ulong(1)<<e);
	}

	public void clear()
	{
		val = 0;
	}

	public bool isEmpty()
	{
		return !val;
	}

	public int opApply(scope int delegate(E e) cb)
	{
		int rv;
		for (size_t i = 0; i < 64; i++)
		{
			ulong bit = ulong(1)<<i;
			if (val & bit)
			{
				rv = cb(cast(E)i);
				if (rv)
					break;
			}
		}
		return rv;
	}

	public size_t count()
	{
		size_t rv;
		for (size_t i = 0; i < 64; i++)
		{
			ulong bit = ulong(1)<<i;
			if (val & bit)
			{
				rv++;
			}
		}
		return rv;
	}
}

unittest
{
	enum E
	{
		a = 1, // test non-zero init
		b = 2,
	}
	EnumSet!E e;
	assert(!e.has(E.a));
	assert(!e.has(E.b));
	e.add(E.a);
	assert( e.has(E.a));
	assert(!e.has(E.b));
	e.add(E.b);
	assert( e.has(E.a));
	assert( e.has(E.b));
	e.remove(E.a);
	assert(!e.has(E.a));
	assert( e.has(E.b));
	e.remove(E.b);
	assert(!e.has(E.a));
	assert(!e.has(E.b));
}

unittest
{
	enum E
	{
		a,
		b,
		c = 62,
		d = 63,
	}
	EnumSet!E e;
	size_t idx;

	e.clear();
	e.add(E.a);
	e.add(E.b);
	//~ e.add(E.c);
	e.add(E.d);
	idx = 0;
	foreach (E val; e)
	{
		switch (idx++)
		{
			case 0: assert(val == E.a); break;
			case 1: assert(val == E.b); break;
			//~ case 2: assert(val == E.c); break;
			case 2: assert(val == E.d); break;
			default:
				//~ import core.stdc.stdio;
				//~ printf("E: %llu\n", cast(ulong)val);
				assert(0);
		}
	}
}
