
all: igraph

########################################################
# Main package

top_srcdir=cigraph
REALVERSION=1.2.6.9001
VERSION=1.2.6.9001

# We put the version number in a file, so that we can detect
# if it changes

version_number: force
	@echo '$(VERSION)' | cmp -s - $@ || echo '$(VERSION)' > $@

# Source files from the C library, we don't need BLAS/LAPACK
# because they are included in R and ARPACK, because 
# we use the Fortran files for that. We don't need F2C, either.

CSRC := $(shell cd $(top_srcdir) ; git ls-files --full-name src | \
	 grep -v "^src/lapack/" | grep -v "^src/f2c" | grep -v Makefile.am)

$(CSRC): src/%: $(top_srcdir)/src/%
	mkdir -p $(@D) && cp $< $@

# Include files from the C library

CINC := $(shell cd $(top_srcdir) ; git ls-files --full-name include)
CINC2 := $(patsubst include/%, src/include/%, $(CINC))

$(CINC2): src/include/%: $(top_srcdir)/include/%
	mkdir -p $(@D) && cp $< $@

# Files generated by flex/bison

PARSER := $(shell cd $(top_srcdir) ; git ls-files --full-name src | \
	    grep -E '\.(l|y)$$')
PARSER1 := $(patsubst src/%.l, src/%.c, $(PARSER))
PARSER2 := $(patsubst src/%.y, src/%.c, $(PARSER1))

YACC=bison -d
LEX=flex

%.c: %.y
	$(YACC) $<
	mv -f y.tab.c $@
	mv -f y.tab.h $(@:.c=.h)

%.c: %.l
	$(LEX) $<
	mv -f lex.yy.c $@

# C files generated by C configure

CGEN = src/igraph_threading.h src/igraph_version.h

src/igraph_threading.h: $(top_srcdir)/include/igraph_threading.h.in
	mkdir -p src
	sed 's/@HAVE_TLS@/0/g' $< >$@

src/igraph_version.h: $(top_srcdir)/include/igraph_version.h.in
	mkdir -p src
	sed 's/@PACKAGE_VERSION@/'$(REALVERSION)'/g' $< >$@

# R source and doc files

RSRC := $(shell git ls-files R man inst demo NEWS configure.win)

# ARPACK Fortran sources

ARPACK := $(shell git ls-files tools/arpack)
ARPACK2 := $(patsubst tools/arpack/%, src/%, $(ARPACK))

$(ARPACK2): src/%: tools/arpack/%
	mkdir -p $(@D) && cp $< $@

# libuuid

UUID := $(shell git ls-files tools/uuid)
UUID2 := $(patsubst tools/uuid/%, src/uuid/%, $(UUID))

$(UUID2): src/uuid/%: tools/uuid/%
	mkdir -p $(@D) && cp $< $@

# R files that are generated/copied

RGEN = R/auto.R src/rinterface.c src/rinterface.h \
	src/rinterface_extra.c src/lazyeval.c src/init.c src/Makevars.in \
	configure src/config.h.in src/Makevars.win \
	DESCRIPTION

# Simpleraytracer

RAY := $(shell cd $(top_srcdir); git ls-files --full-name optional/simpleraytracer)
RAY2 := $(patsubst optional/simpleraytracer/%, \
	  src/simpleraytracer/%, $(RAY))

$(RAY2): src/%: $(top_srcdir)/optional/%
	mkdir -p $(@D) && cp $< $@

# Files generated by stimulus

src/rinterface.c: $(top_srcdir)/interfaces/functions.def \
		tools/stimulus/rinterface.c.in  \
		tools/stimulus/types-C.def \
		$(top_srcdir)/tools/stimulus.py
	$(top_srcdir)/tools/stimulus.py \
           -f $(top_srcdir)/interfaces/functions.def \
           -i tools/stimulus/rinterface.c.in \
           -o src/rinterface.c \
           -t tools/stimulus/types-C.def \
           -l RC

R/auto.R: $(top_srcdir)/interfaces/functions.def tools/stimulus/auto.R.in \
		tools/stimulus/types-R.def \
		$(top_srcdir)/tools/stimulus.py
	$(top_srcdir)/tools/stimulus.py \
           -f $(top_srcdir)/interfaces/functions.def \
           -i tools/stimulus/auto.R.in \
           -o R/auto.R \
           -t tools/stimulus/types-R.def \
           -l RR

# configure files

configure src/config.h.in: configure.ac
	autoheader; autoconf

# DESCRIPTION file, we re-generate it only if the VERSION number
# changes or $< changes

DESCRIPTION: tools/stimulus/DESCRIPTION version_number
	sed 's/^Version: .*$$/Version: '$(VERSION)'/' $< > $@

src/rinterface.h: tools/stimulus/rinterface.h
	mkdir -p src
	cp $< $@

src/rinterface_extra.c: tools/stimulus/rinterface_extra.c
	mkdir -p src
	cp $< $@

src/lazyeval.c: tools/stimulus/lazyeval.c
	mkdir -p src
	cp $< $@

src/init.c: tools/stimulus/init.c
	mkdir -p src
	cp $< $@

# This is the list of all object files in the R package,
# we write it to a file to be able to depend on it.
# Makevars.in and Makevars.win are only regenerated if 
# the list of object files changes.

OBJECTS := $(shell echo $(CSRC) $(ARPACK) $(RAY) $(UUID)   |             \
		tr ' ' '\n' |                                            \
	        grep -E '\.(c|cpp|cc|f|l|y)$$' | 			 \
		grep -F -v '/t_cholmod' | 				 \
		grep -F -v f2c/arithchk.c | grep -F -v f2c_dummy.c |	 \
		sed 's/\.[^\.][^\.]*$$/.o/' | 			 	 \
		sed 's/^src\///' | sed 's/^tools\/arpack\///' |		 \
		sed 's/^tools\///' | 					 \
		sed 's/^optional\///') rinterface.o rinterface_extra.o lazyeval.o

object_files: force
	@echo '$(OBJECTS)' | cmp -s - $@ || echo '$(OBJECTS)' > $@

configure.ac: %: tools/stimulus/%
	sed 's/@VERSION@/'$(VERSION)'/g' $< >$@

src/Makevars.win src/Makevars.in: src/%: tools/stimulus/% \
		object_files
	sed 's/@VERSION@/'$(VERSION)'/g' $< >$@
	printf "%s" "OBJECTS=" >> $@
	cat object_files >> $@

# We have everything, here we go

igraph: igraph_$(VERSION).tar.gz

igraph_$(VERSION).tar.gz: $(CSRC) $(CINC2) $(PARSER2) $(RSRC) $(RGEN) \
			  $(CGEN) $(RAY2) $(ARPACK2) $(UUID2)
	rm -f src/config.h
	rm -f src/Makevars
	touch src/config.h
	mkdir -p man
	tools/builddocs.sh
	Rscript -e 'devtools::build(path = ".")'
#############

.PHONY: all igraph force

.NOTPARALLEL:
