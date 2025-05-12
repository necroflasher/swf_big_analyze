module swfbiganal.swf.tagtimestat;

import core.stdc.stdlib;
import core.stdc.stdio;
import swfbiganal.util.commaize;
import swfbiganal.swftypes.swftag;

import core.memory : GC;
import core.time : Duration, MonoTime; // SLOW!!!

private struct OutputRow
{
	uint tagCode;
	TagTimeStat.TagCollectedInfo* info;
}

private int compare(T)(T x, T y)
{
	// https://en.wikipedia.org/wiki/Qsort#Example
	// like "x - y" but without overflowing
	return (x > y) - (x < y);
}

extern (C)
private int TagTimeStat_rowSortFunc(const(void)* aa, const(void)* bb)
{
	OutputRow* a = cast(OutputRow*)aa;
	OutputRow* b = cast(OutputRow*)bb;

	if (a.info.totalTime != b.info.totalTime)
		return -compare(a.info.totalTime, b.info.totalTime);

	if (a.info.parseCount != b.info.parseCount)
		return -compare(a.info.parseCount, b.info.parseCount);

	return -compare(a.tagCode, b.tagCode);
}

struct TagTimeStat
{
	struct TagCollectedInfo
	{
		Duration totalTime;
		ulong    totalGcSize;
		size_t   parseCount;
	}

	// totals
	TagCollectedInfo[SwfTotalPossibleTagCodes] allTags;

	// current tag
	MonoTime startTime;
	ulong    startGcSize;

	void start()
	{
		startTime = MonoTime.currTime;
		startGcSize = GC.allocatedInCurrentThread();
	}

	void end(uint tagCode)
	{
		auto endTime = MonoTime.currTime;
		auto endGcSize = GC.allocatedInCurrentThread();
		auto info = &allTags[tagCode];
		info.totalTime += (endTime - startTime);
		info.totalGcSize += (endGcSize - startGcSize);
		info.parseCount += 1;
	}

	void printTotals()
	{
		OutputRow[] rows;

		foreach (uint tagCode, ref info; allTags)
		{
			if (info.parseCount > 0)
				rows ~= OutputRow(tagCode, &info);
		}

		qsort(rows.ptr, rows.length, OutputRow.sizeof, &TagTimeStat_rowSortFunc);

		ulong totalGcSize;
		fprintf(stderr, "     Cnt  Tag                                 Gc  Total       Avg\n");
		foreach (ref row; rows)
		{
			// 23 = longest tag name
			fprintf(stderr, "%8zu  %-23s  %7llu bytes  %.3f msec  avg %.3f msec\n",
				row.info.parseCount,
				SwfTag.name(row.tagCode),
				row.info.totalGcSize,
				row.info.totalTime.total!"usecs"/1000.0,
				(row.info.totalTime.total!"usecs"/row.info.parseCount)/1000.0,
				);
			totalGcSize += row.info.totalGcSize;
		}

		char[27] buf = void;
		fprintf(stderr, "GC total: %s bytes\n", totalGcSize.commaize(buf));
	}
}
