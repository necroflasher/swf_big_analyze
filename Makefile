analyze_SRCS = \
	$(shell find src/ -name '*.d' -not -path 'src/bin/*.d') \
	src/bin/analyze.d \

analyze_LIBS = -llzma -lxxhash

DMD ?= dmd -defaultlib=libphobos2.so -g -L=-fuse-ld=lld
LDC ?= ldc2 --disable-verify --gline-tables-only --link-defaultlib-shared
GDC ?= gdc -g -fno-moduleinfo -fno-weak-templates

ifeq ($(DEBUG),1)
DMDFLAGS += -debug
LDCFLAGS += --d-debug --enable-inlining=false
GDCFLAGS += -fdebug
endif
ifeq ($(OPT),1)
DMDFLAGS += -O -inline -mcpu=native
LDCFLAGS += -O3 -flto=full -mcpu=native --fvisibility=hidden
GDCFLAGS += -O3 -flto=auto -march=native -fvisibility=hidden -fno-exceptions
endif
ifeq ($(RELEASE),1)
# don't recommend even though i haven't seen a violation in ages
DMDFLAGS += -release -boundscheck=off -checkaction=halt
LDCFLAGS += --release --boundscheck=off --checkaction=halt
GDCFLAGS += -frelease -fbounds-check=off -fcheckaction=halt
endif

ifneq ($(M),)
DMDFLAGS += -m$(M)
LDCFLAGS += -m$(M)
GDCFLAGS += -m$(M)
ifeq ($(M),32)
DMDFLAGS += -fPIC
endif
endif

# always recompile in "make watch"
ifeq ($(MAKELEVEL),1)
.PHONY: analyze
.PHONY: analyze2
.PHONY: analyze3
endif

analyze: $(analyze_SRCS)
	$(DMD) $(DMDFLAGS) $^ -of=$@ $(addprefix -L=,$(analyze_LIBS)) && size $@

analyze2: $(analyze_SRCS)
	$(LDC) $(LDCFLAGS) $^ --of=$@ $(addprefix --L=,$(analyze_LIBS)) && size $@

analyze3: $(analyze_SRCS)
	$(GDC) $(GDCFLAGS) $^ -o $@ $(analyze_LIBS) && size $@

.PHONY: watch watchldc watchgdc
watch:
	ls $(analyze_SRCS) | entr -cs 'make -s'
watchldc:
	ls $(analyze_SRCS) | entr -cs 'make -s analyze2'
watchgdc:
	ls $(analyze_SRCS) | entr -cs 'make -s analyze3'

_test_analyze: DMDFLAGS += -unittest
_test_analyze: $(analyze_SRCS)
	$(DMD) $(DMDFLAGS) $^ -of=$@ $(addprefix -L=,$(analyze_LIBS)) && size $@
_test_analyze2: LDCFLAGS += --unittest
_test_analyze2: $(analyze_SRCS)
	$(LDC) $(LDCFLAGS) $^ --of=$@ $(addprefix --L=,$(analyze_LIBS)) && size $@
_test_analyze3: GDCFLAGS += -funittest -fmoduleinfo
_test_analyze3: $(analyze_SRCS)
	$(GDC) $(GDCFLAGS) $^ -o $@ $(analyze_LIBS) && size $@

.PHONY: test test2 test3
test: _test_analyze
	./_test_analyze
test2: _test_analyze2
	./_test_analyze2
test3: _test_analyze3
	./_test_analyze3

.PHONY: watchtest
watchtest:
	ls $(analyze_SRCS) | entr -cs 'make -s test'

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
