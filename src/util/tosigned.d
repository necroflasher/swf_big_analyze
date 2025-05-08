module swfbiganal.util.tosigned;

auto toSigned(U)(U value, uint numbits)
{
	static assert(U.min == 0, U.stringof~" is not an unsigned type");

	/**/ static if (is(U == ubyte))  alias S = byte;
	else static if (is(U == ushort)) alias S = short;
	else static if (is(U == uint))   alias S = int;
	else static if (is(U == ulong))  alias S = long;
	else static assert(0, "no corresponding signed type for '"~U.stringof);

	const U topbit = cast(U)( U(1) << (numbits-1) );
	if (value & topbit)
	{
		value ^= topbit;                 // remove sign bit
		value = cast(U)(topbit - value); // reverse value
		value = cast(U)-value;           // negate
	}

	return cast(S)value;
}

unittest
{
	assert(toSigned!ubyte(0b1111, 4) == -1);
	assert(toSigned!ubyte(0b1110, 4) == -2);

	assert(toSigned!uint(0b1111, 4) == -1);
	assert(toSigned!uint(0b1110, 4) == -2);

	assert(toSigned!ushort(0b1111, 4) == -1);
	assert(toSigned!ushort(0b1110, 4) == -2);

	assert(toSigned!ulong(0b1111, 4) == -1);
	assert(toSigned!ulong(0b1110, 4) == -2);
}
