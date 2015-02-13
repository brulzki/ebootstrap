ebootstrap
==========

A stage3 installer for gentoo.

The idea for this script was conceived from Debian's debootstrap. I have
always been jealous of how it is possible to install a basic debian system
into a target directory with a single debootstrap command, and this script
attempts to replicate that experience. However a gentoo system will
typically require a lot of extra post-install configuration to get to a
usable state.

This script is not intended to be a complete installer; preparation tasks,
such as disk partitioning or encryption configuration should be performed
prior to this script, and configuration tasks, such as bootloader and system
configuration will be required after this script. This script is intended to
be sufficiently generic that it can be called from an installer script to
perform the stage3 installation in a wide variety of circumstances, such as
chroot or container creation, or full installation to a real or virtual
machine.

The implementation is based on portage ebuilds.

Usage
-----

ebootstrap CONFIG TARGET

License
-------
Distributed under the terms of the GNU General Public License v2.

The license was chosed to be compatible with gentoo portage.

Inspirations
------------

It has been inspired by the numerous other scripts which do a similar task
for a specific use case, and it is intended that this script could replace
the stage3 creation phase in any of these:

 - lxc-gentoo [1]: Performs a stage3 install, with some lxc specific tweaks
   and creates a lxc config file. Has a nice caching feature. This was the
   inital basis for the gentoo-stage3 script; much of the code was taken
   from here initially, since the code was simple and clean enough to reuse
   and had a nice cacheing feature, but I wanted a script to create a chroot
   directory without the lxc configuration.

 - kicktoo [2]: Designed to be a compelte installer solution. Has the ability to
   partition and format disks prior to the stage3 install, and can do lots
   of the post-stage3 configuration.

 - Amazon EC2 gentoo bootstrap [3]

[1] https://github.com/globalcitizen/lxc-gentoo
[2] https://github.com/r1k0/kicktoo
[3] https://github.com/rich0/rich0-gentoo-bootstrap
