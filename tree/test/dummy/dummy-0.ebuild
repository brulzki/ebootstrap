# Copyright (c) 2015 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

EAPI=5

inherit ebootstrap

DESCRIPTION="This is a test stage ebuild for ebootstrap"
HOMEPAGE="http://github.com/brulzki/ebootstrap"
SRC_URI="http:///github.com/brulzki/ebootstrap/stage3-dummy.tar.xz"
#LICENSE=""
SLOT="0"
KEYWORDS="ebootstrap"
#IUSE=""
#DEPEND=""
#RDEPEND=""

E_PROFILE=dummy
E_PORTDIR=/var/db/portage/gentoo
E_DISTDIR=/var/cache/distfiles
E_PKGDIR=/var/cache/packages
