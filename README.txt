swf_big_analyze (swfbiganal)

tool i wrote to convert swf to a textual data dump, and extract some
 interesting stuff from them (mainly strings and hidden data)

the intended use is to run it on a collection of flashes and redirect the
 output to a single text file which you'd then search (using grep/awk) to find
 swf files that contain some feature you're interested in

example output:

  % ./swfbiganal3 ~/flash/idgaf.swf
  file 603713 /home/user/flash/idgaf.swf
  swf-header CWS 7 607842
  zlib-header 8 7 28 n 2 -
  movie-header 15 0 11000 0 8000 00-0c 1
  !background-color #ffffff
  !export idgaf%20(Loop)
  !as2-string loop
  !as2-string Sound
  !as2-string idgaf%20(Loop)
  !as2-string attachSound
  !as2-string start
  !font-name Comic%20Sans%20MS
  !text-string2 Ghostface%20Playa%20-%20I%20Don't%20Give%20a%20Fuck
  swf-data-total 607834 90bacfbc

--- old readme below ---

swf big data analysis

converts .swf files into a greppable text format, containing
- a line for each header structure and the values in it
- lengths and checksums of tags and their data
- lengths and checksums of unused/hidden data in the swf (several possible places)
- text strings parsed from tags

goalz
- graceful handling of buggy/corrupt/malicious files
- parse all valid data, stop where flash player would also stop
- don't let crafted files explode memory use (theoretical maximum is 2GB, the
   largest possible swf with the largest possible tag size)

TODO:
- extract: bg color
- extract strings from DefineFont3+DefineText
  - DefineFont3 => parse, save glyph index -> character code
  - DefineText => look up given glyphs to get the characters
- what tags have strings (user-provided text) but aren't indexed?
  - 77:Metadata -> xml metadata
  - 86:DefineSceneAndFrameLabelData -> scene name
  - 88:DefineFontName -> font name
