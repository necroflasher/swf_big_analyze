module swfbiganal.util.datacrc;

import swfbiganal.appenders.junkappender;

/**
 * Some data and its CRC + total size, basically a wrapper for a JunkAppender's
 * result.
 */
struct DataCrc
{
	const(ubyte)[] data;
	uint           crc;
	ulong          total;

	const(ubyte)[] opSlice()
	{
		return data;
	}

	static DataCrc from(ref const(JunkAppender) ja)
	{
		return DataCrc(ja[], ja.crc, ja.total);
	}
}
