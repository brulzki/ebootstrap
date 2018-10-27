# Copyright (c) 2018 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

EAPI=6

DESCRIPTION="ebootstrap"
HOMEPAGE="https://github.com/brulzki/ebootstrap"

if [[ ${PV} = 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="git://github.com/brulzki/${PN}.git
		https://github.com/brulzki/${PN}.git"
	KEYWORDS=""
else
	SRC_URI="https://github.com/brulzki/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm64 ~ppc ~ppc64 ~x86"
fi

LICENSE="GPL-2"
SLOT="0"
