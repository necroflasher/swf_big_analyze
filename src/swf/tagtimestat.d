module swfbiganal.swf.tagtimestat;

import core.stdc.stdio;
import swfbiganal.util.commaize;
import swfbiganal.swftypes.swftag;

// SLOW!!!
import core.memory : GC;
import core.time : Duration, MonoTime;
import std.algorithm.sorting : sort;

struct TagTimeStat
{
	struct TagCollectedInfo
	{
		Duration totalTime;
		ulong    totalGcSize;
		size_t   parseCount;
	}
	static TagCollectedInfo[SwfTotalPossibleTagCodes] allTags;

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

	static void printTotals()
	{
		struct OutputRow
		{
			uint tagCode;
			TagCollectedInfo* info;
		}

		OutputRow[] rows;
		foreach (uint tagCode, ref info; allTags)
		{
			if (info.parseCount > 0)
			{
				rows ~= OutputRow(tagCode, &info);
			}
		}

		auto sorted = rows.sort!((a, b)
		{
			// ORDER BY totalTime DESC, parseCount DESC, tagCode ASC
			// (comment out to remove that column from the sort)
			if (a.info.totalTime != b.info.totalTime) return a.info.totalTime > b.info.totalTime;
			if (a.info.parseCount != b.info.parseCount) return a.info.parseCount > b.info.parseCount;
			return a.tagCode < b.tagCode;
		});

		ulong totalGcSize;
		fprintf(stderr, "     Cnt  Tag                                 Gc  Total       Avg\n");
		foreach (ref row; sorted)
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
		fprintf(stderr, "GC total: %s\n", totalGcSize.commaize(buf));
	}
}
