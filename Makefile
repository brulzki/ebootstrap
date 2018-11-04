# Copyright (c) 2018 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

#.PHONY: all
all:

PREFIX ?= /usr
INSTALL ?= install
bindir ?= $(PREFIX)/bin
libdir ?= $(PREFIX)/lib/ebootstrap

#.PHONY: install
install:
	mkdir -m 755 -p $(DESTDIR)$(libdir)
	mkdir -m 755 -p $(DESTDIR)$(bindir)
	$(INSTALL) -m 644 -t $(DESTDIR)$(libdir) lib/ebootstrap-core.sh
	$(INSTALL) -m 644 -t $(DESTDIR)$(libdir) lib/ebootstrap-backend-default.sh
	$(INSTALL) -m 644 -t $(DESTDIR)$(libdir) lib/ebootstrap-functions.sh
	$(INSTALL) -m 644 -t $(DESTDIR)$(libdir) lib/ebootstrap.eclass

	mkdir -m 755 -p $(DESTDIR)$(libdir)/eroot
	$(INSTALL) -m 644 -t $(DESTDIR)$(libdir)/eroot lib/eroot/stage3.eroot

	sed 's!^EBOOTSTRAP_LIB=.*/lib$$!EBOOTSTRAP_LIB=$(libdir)!' ebootstrap > $(DESTDIR)$(bindir)/ebootstrap
	chmod 755 $(DESTDIR)$(bindir)/ebootstrap

.PHONY: all install
