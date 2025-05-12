SRCS = src/*.d src/*/*.d

DMD     ?= dmd -defaultlib=libphobos2.so -g -L=-fuse-ld=lld
DMDLIBS += -L=-llzma -L=-lxxhash

LDC     ?= ldc2 --disable-verify --gline-tables-only --link-defaultlib-shared
LDCLIBS += --L=-llzma --L=-lxxhash

GDC     ?= gdc -g -fno-moduleinfo -fno-weak-templates
GDCLIBS += -llzma -lxxhash

ifeq ($(DEBUG),1)
DMDFLAGS += -debug
LDCFLAGS += --d-debug --enable-inlining=false
GDCFLAGS += -fdebug
endif
ifeq ($(OPT),1)
DMDFLAGS += -O -inline -mcpu=native
LDCFLAGS += -O3 -flto=full -mcpu=native --fvisibility=hidden -fno-exceptions
GDCFLAGS += -O2 -flto=auto -march=native -fvisibility=hidden -fno-exceptions
endif
ifeq ($(RELEASE),1)
# don't recommend even though i haven't seen a violation in ages
DMDFLAGS += -release -boundscheck=off -checkaction=halt
LDCFLAGS += --release --boundscheck=off --checkaction=halt
GDCFLAGS += -frelease -fbounds-check=off -fcheckaction=halt
endif

# always recompile in "make watch"
ifeq ($(MAKELEVEL),1)
.PHONY: swfbiganal
.PHONY: swfbiganal2
.PHONY: swfbiganal3
endif

swfbiganal: $(SRCS)
	$(DMD) $(DMDFLAGS) $^ -of=$@ $(DMDLIBS) && size $@

swfbiganal2: $(SRCS)
	$(LDC) $(LDCFLAGS) $^ --of=$@ $(LDCLIBS) && size $@

swfbiganal3: $(SRCS)
	$(GDC) $(GDCFLAGS) $^ -o $@ $(GDCLIBS) && size $@

.PHONY: watch watchldc watchgdc
watch:
	ls $(SRCS) | entr -cs 'make -s'
watchldc:
	ls $(SRCS) | entr -cs 'make -s swfbiganal2'
watchgdc:
	ls $(SRCS) | entr -cs 'make -s swfbiganal3'

_test_swfbiganal: DMDFLAGS += -unittest
_test_swfbiganal: LDCFLAGS += --unittest
_test_swfbiganal: GDCFLAGS += -funittest -fmoduleinfo
_test_swfbiganal: $(SRCS)
#	$(DMD) $(DMDFLAGS) $^ -of=$@ $(DMDLIBS) && size $@
#	$(LDC) $(LDCFLAGS) $^ --of=$@ $(LDCLIBS) && size $@
	$(GDC) $(GDCFLAGS) $^ -o $@ $(GDCLIBS) && size $@

.PHONY: test
test: _test_swfbiganal
	./_test_swfbiganal

.PHONY: watchtest
watchtest:
	ls $(SRCS) | entr -cs 'make -s test'

.PHONY: todo
todo:
	-@grep -Einr --color=auto '(CLEANUP|FIXME|REFACTOR|TODO|XXX)([(:]|$$)' src/

.PHONY: lint
lint:
# pragma(inline) should be inside the function with a semicolon at the end
	@grep -Enr --color=auto 'pragma\(inline.*\)($$|[^;])' src/ ||:
# attributes like this need a semicolon at the end of the line so geany's parsing doesn't break
	@grep -Enr --color=auto '^(\s*(nothrow|@nogc))+:$$' src/ ||:
# standard lib imports tend to slow down compilation
	@grep -Pnr --color=auto 'import (std\.|core\.(?!stdc|sys))(?!.*grep:)' src/ ||:
