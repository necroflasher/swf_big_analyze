module swfbiganal.util.string;

import core.stdc.string;

inout(char)[] fromStringz(inout(char)* str)
{
	if (str != null)
	{
		return str[0..strlen(str)];
	}
	else
	{
		return null;
	}
}
