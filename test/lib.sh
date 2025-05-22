mkdir -p test/swf
passfilenum=1
failfilenum=1
rm -f test/swf/*.swf
shouldpass() {
	ln "$1" test/swf/pass$passfilenum.swf
	passfilenum=$((passfilenum+1))
}
shouldfail() {
	ln "$1" test/swf/fail$failfilenum.swf
	failfilenum=$((failfilenum+1))
}
