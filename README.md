# swf_big_analyze

## about

this is a tool i wrote to read swf files and extract some interesting stuff from
 them (mainly strings and hidden data)

the intended use is to run it on a big collection of flashes, saving the output
 to a single file, then search it using grep/awk to find flashes that contain
 some thing you're interested in

## some good things about it

- does not blow up on buggy/malicious/corrupt files
- attempts to detect corrupt/unopenable files the same way flash player does
- theoretical peak memory use is around 2GB, the largest possible tag size

## example output

```
% ./analyze3 ~/flash/idgaf.swf
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
```

## efficiently searching gigabytes of output

these examples search for a specific printed warning (AS2 undocumented opcode)
 in an output file named `analyze.out`

```
# print path and matching line
rg '^file|^#!.*AS2 undocumented' analyze.out | mawk '
/^f/ { fileline=$0; next; }
{ tmp=$0; $0=fileline; print($3 ": " tmp); }
'
```

```
# just list files that have a matching line
rg '^file|^#!.*AS2 undocumented' analyze.out | mawk '
/^f/ { fileline=$0; next; }
fileline!="" { tmp=$0; $0=fileline; print($3); fileline=""; }
'
```

what makes them fast is
- they use rg and mawk instead of grep and gawk
- rg filters the huge mass of lines so mawk has less work to do
- the mawk block for the file line does as little work as possible (rg can't
   filter them so it still gets one for every file ever)

## compiling

install one of the [D compilers](https://dlang.org/download.html), then run one
 of the commands below

note that if you have `gcc` installed using a package manager, it's likely that
 you can get `gdc` from the same source

```
# with dmd
make analyze

# with ldc
make analyze2 OPT=1

# with gdc
make analyze3 OPT=1
```

## known differences from flash player

- when flash player parses tag contents, it can in some cases read past the end
   of the tag data, taking in bytes from the rest of the file. for example, a
   SetBackgroundColor tag with only 2 of 3 bytes will still work, and the last
   RGB component will depend on what comes next in the file. swf_big_analyze
   currently doesn't implement this
