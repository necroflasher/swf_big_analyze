module swfbiganal.util.commaize;

const(char)* commaize(U, B)(U v, ref B buf)
if (is(U == ulong) || is(U == uint) || is(U == ushort) || is(U == ubyte))
{
	static if (is(U == ulong))
		enum maxlen = 26; // "18,446,744,073,709,551,615"
	else static if (is(U == uint))
		enum maxlen = 13; // "4,294,967,295"
	else static if (is(U == ushort))
		enum maxlen = 6; // "65,535"
	else static if (is(U == ubyte))
		enum maxlen = 3; // "255"
	else
		static assert(0);

	static assert(buf.length >= maxlen+1);

	char *p = &buf[maxlen];
	size_t i;
	*p-- = 0;
	if (v)
		do
		{
			*p-- = '0' + v % 10;
			v /= 10;
			if (v && i++ % 3 == 2) *p-- = ',';
		}
		while (v);
	else
		*p-- = '0';
	return p+1;
}
