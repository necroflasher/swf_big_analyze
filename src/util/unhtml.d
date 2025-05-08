module swfbiganal.util.unhtml;

import swfbiganal.util.appender;

/**
 * remove html tags from a string (for DefineText)
 */
void unhtml(
	const(char)[] str,
	scope void delegate(scope const(char)[]) cb)
{
	ScopedAppender!(char[]) ap;
	unhtml(str, ap);
	cb(ap[]);
}

// -----------------------------------------------------------------------------

private:

/**
 * remove html tags from a string (for DefineText)
 */
void unhtml(const(char)[] str, ref ScopedAppender!(char[]) ap)
{
	bool          intag;
	int           putspace = 2; // if prev char was: newline->2 space->1 other->0
	size_t        skiptimes;
	const(char)[] tagname;
	foreach (i, char c; str)
	{
		if (skiptimes){skiptimes--;continue;}
		if (c == '<')
		{
			intag = true;
			// get the tag name
			auto rest = str[i+1..$].leftTrim;
			foreach (ii, cc; rest) if (cc <= ' ' || cc == '>') { rest = rest[0..ii]; break; }
			tagname = rest;
			switch (tagname)
			{
				case "li":
				case "LI":
					ap ~= "* ";
					putspace = 1;
					break;
				default:
					break;
			}
		}
		else if (c == '>')
		{
			intag = false;
			if (putspace != 2)
			{
				switch (tagname)
				{
					case "/p":
					case "/P":
					case "br":
					case "BR":
					case "/br":
					case "/BR":
						if (putspace == 1) trimTrailingSpaces(ap);
						ap ~= '\n';
						putspace = 2;
						break;
					default:
						break;
				}
			}
		}
		else if (!intag)
		{
			if (c == '&')
			{
				struct Rep
				{
					string entity;
					char replacement;
				}
				static immutable reps = [
					Rep("&amp;", '&'),
					Rep("&quot;", '"'),
					Rep("&lt;", '<'),
					Rep("&gt;", '>'),
					Rep("&apos;", '\''),
					Rep("&nbsp;", ' '),
				];
				foreach (ref rep; reps)
				{
					if (str.length-i >= rep.entity.length && str[i..i+rep.entity.length] == rep.entity)
					{
						c = rep.replacement;
						skiptimes = rep.entity.length-1;
						break;
					}
				}
			}
			int spacetype;
			if (c == '\n')
			{
				if (putspace == 1) trimTrailingSpaces(ap);
				spacetype = 2;
			}
			else
			{
				spacetype = c <= ' ';
			}
			if (
				spacetype == 0 ? true :
				spacetype == 1 ? !putspace :
				spacetype == 2 ? putspace != 2 :
			false)
			{
				ap ~= c;
				putspace = spacetype;
			}
		}
	}
	if (putspace)
	{
		while (ap[].length && ap[][$-1] <= ' ')
			ap.shrinkTo(ap[].length-1);
	}
	// kek.swf: !text-string [CHECK&apo%0as;EM]
}

// -----------------------------------------------------------------------------

private:

const(char)[] leftTrim(const(char)[] str)
{
	foreach (i, c; str)
	{
		if (c > ' ')
			return str[i..$];
	}
	return str[0..0];
}
unittest
{
	assert(" asd ".leftTrim == "asd ");
	assert("  asd".leftTrim == "asd");
	assert(" ".leftTrim == "");
	assert("".leftTrim == "");
}

const(char)[] rightTrim(const(char)[] str)
{
	foreach_reverse (i, c; str)
	{
		if (c > ' ')
			return str[0..i+1];
	}
	return str[$..$];
}
unittest
{
	assert(" asd ".rightTrim == " asd");
	assert("asd  ".rightTrim == "asd");
	assert(" ".rightTrim == "");
	assert("".rightTrim == "");
}

void trimTrailingSpaces(ref ScopedAppender!(char[]) ap)
{
	size_t cnt;
	foreach_reverse (c; ap[])
	{
		if (c <= ' ' && c != '\n')
			cnt++;
		else
			break;
	}
	if (cnt)
		ap.shrinkTo(ap[].length-cnt);
}

version(unittest)
string unhtml(string str)
{
	string rv;
	unhtml(str, (scope s)
	{
		rv = s.idup;
	});
	return rv;
}

unittest
{
	assert(unhtml("<b>hi</b>") == "hi");
	assert(unhtml("<p>hi</p>") == "hi");
	assert(unhtml("<p>hi1</p><p>hi2</p>") == "hi1\nhi2");
	assert(unhtml("<p>hi1</p><p></p><p>hi2</p>") == "hi1\nhi2");
	assert(unhtml("&gt;implying") == ">implying");
	assert(unhtml("&gt;") == ">");
	assert(unhtml("&nbsp;") == ""); // uh
	assert(unhtml("&nbsp") == "&nbsp");
	assert(unhtml("a &amp; b") == "a & b");
	assert(unhtml("a \nb") == "a\nb");
	assert(unhtml("a\n b") == "a\nb");
	assert(unhtml("a \n b") == "a\nb");
	assert(unhtml("a b") == "a b");
	assert(unhtml("a\nb") == "a\nb");
	assert(unhtml("a  b") == "a b");
	assert(unhtml("a\n\nb") == "a\nb");
	assert(unhtml("a<br>b") == "a\nb");
	assert(unhtml("a<  br  >b") == "a\nb");
	assert(unhtml("a <br> b") == "a\nb");
	assert(unhtml(" \n \n hi \n \n ") == "hi");
	assert(unhtml(" \n \n hi \n \n \n") == "hi");
}
