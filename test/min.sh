
. test/lib.sh

# rect  1 -> min header size 21, min tag data 8 (rect+tags=9)
# rect  2 -> min header size 21, min tag data 7 (rect+tags=9)
# rect  3 -> min header size 21, min tag data 6 (rect+tags=9)
# rect  4 -> min header size 22, min tag data 6 (rect+tags=10)
# rect  5 -> min header size 23, min tag data 6 (rect+tags=11)
# rect  6 -> min header size 24, min tag data 6 (rect+tags=12)
# rect  7 -> min header size 25, min tag data 6 (rect+tags=13)
# rect  8 -> min header size 26, min tag data 6 (rect+tags=14)
# rect  9 -> min header size 27, min tag data 6 (rect+tags=15)
# rect 10 -> min header size 28, min tag data 6 (rect+tags=16)
# rect 11 -> min header size 29, min tag data 6 (rect+tags=17)
# rect 12 -> min header size 30, min tag data 6 (rect+tags=18)
# rect 13 -> min header size 31, min tag data 6 (rect+tags=19)
# rect 14 -> min header size 32, min tag data 6 (rect+tags=20)
# rect 15 -> min header size 33, min tag data 6 (rect+tags=21)
# rect 16 -> min header size 34, min tag data 6 (rect+tags=22)
# rect 17 -> min header size 35, min tag data 6 (rect+tags=23)

# tested:
# flashplayerdebugger32_0r0_465
# flashplayerdebugger11_2r202_644

generate() {
	header_size=$1
	rect_size=$2
	tags_size=$3
	echo "%include 'test/lib.asm'"
	echo "db 'FWS',1"
	echo "dd ${header_size}"
	echo "DummyRect${rect_size}"
	echo "db 0, 0"
	echo "db 0, 0"
	echo "times ${tags_size} db 0"
}

for rect_size in $(seq 1 17); do
	case $rect_size in
	1) tags_min=8;;
	2) tags_min=7;;
	*) tags_min=6;;
	esac
	header_min=$((12+rect_size+tags_min))

	# as given
	rm -f test.swf
	generate $header_min $rect_size $tags_min >test.swf.asm
	yasm test.swf.asm || exit
	shouldpass test.swf
	if ! ./analyze test.swf >/dev/null; then
		./analyze test.swf -tags
		echo fail
		exit 1
	fi

	# tags minus 1
	rm -f test.swf
	generate $header_min $rect_size $((tags_min-1)) >test.swf.asm
	yasm test.swf.asm || exit
	shouldfail test.swf
	if ./analyze test.swf >/dev/null; then
		./analyze test.swf -tags
		echo fail
		exit 1
	fi

	# header size minus 1
	rm -f test.swf
	generate $((header_min-1)) $rect_size $tags_min >test.swf.asm
	yasm test.swf.asm || exit
	shouldfail test.swf
	if ./analyze test.swf >/dev/null; then
		./analyze test.swf -tags
		echo fail
		exit 1
	fi
done

exit 0
