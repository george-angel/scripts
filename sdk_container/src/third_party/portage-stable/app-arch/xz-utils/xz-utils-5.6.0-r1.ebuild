# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# Remember: we cannot leverage autotools in this ebuild in order
#           to avoid circular deps with autotools

EAPI=8

inherit flag-o-matic libtool multilib multilib-minimal preserve-libs toolchain-funcs

if [[ ${PV} == 9999 ]] ; then
	# Per tukaani.org, git.tukaani.org is a mirror of github and
	# may be behind.
	EGIT_REPO_URI="
		https://github.com/tukaani-project/xz
		https://git.tukaani.org/xz.git
	"
	inherit git-r3 autotools

	# bug #272880 and bug #286068
	BDEPEND="sys-devel/gettext >=dev-build/libtool-2"
else
	VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/jiatan.asc
	inherit verify-sig

	MY_P="${PN/-utils}-${PV/_}"
	SRC_URI="
		https://github.com/tukaani-project/xz/releases/download/v${PV/_}/${MY_P}.tar.gz
		mirror://sourceforge/lzmautils/${MY_P}.tar.gz
		https://tukaani.org/xz/${MY_P}.tar.gz
		verify-sig? (
			https://github.com/tukaani-project/xz/releases/download/v${PV/_}/${MY_P}.tar.gz.sig
			https://tukaani.org/xz/${MY_P}.tar.gz.sig
		)
	"

	if [[ ${PV} != *_alpha* && ${PV} != *_beta* ]] ; then
		KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~ia64 ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86 ~amd64-linux ~x86-linux ~arm64-macos ~ppc-macos ~x64-macos ~x64-solaris"
	fi

	S="${WORKDIR}/${MY_P}"
fi

DESCRIPTION="Utils for managing LZMA compressed files"
HOMEPAGE="https://tukaani.org/xz/"

# See top-level COPYING file as it outlines the various pieces and their licenses.
LICENSE="0BSD LGPL-2.1+ GPL-2+ doc? ( CC-BY-SA-4.0 )"
SLOT="0"
IUSE="cpu_flags_arm_crc32 doc +extra-filters pgo nls static-libs"

if [[ ${PV} != 9999 ]] ; then
	BDEPEND+=" verify-sig? ( sec-keys/openpgp-keys-jiatan )"
fi

PATCHES=(
	"${FILESDIR}"/${P}-logging-verbosity-threads-auto.patch
)

src_prepare() {
	default

	if [[ ${PV} == 9999 ]] ; then
		eautopoint
		eautoreconf
	else
		# Allow building shared libs on Solaris/x64
		elibtoolize
	fi
}

multilib_src_configure() {
	local myconf=(
		--enable-threads
		$(multilib_native_use_enable doc)
		$(use_enable nls)
		$(use_enable static-libs static)
		$(use_enable cpu_flags_arm_crc32 arm64-crc32)
	)

	if ! multilib_is_native_abi ; then
		myconf+=(
			--disable-{xz,xzdec,lzmadec,lzmainfo,lzma-links,scripts}
		)
	fi

	if ! use extra-filters ; then
		myconf+=(
			# LZMA1 + LZMA2 for standard .lzma & .xz files
			--enable-encoders=lzma1,lzma2
			--enable-decoders=lzma1,lzma2

			# those are used by default, depending on preset
			--enable-match-finders=hc3,hc4,bt4

			# CRC64 is used by default, though some (old?) files use CRC32
			--enable-checks=crc32,crc64
		)
	fi

	if [[ ${CHOST} == *-solaris* ]] ; then
		export gl_cv_posix_shell="${EPREFIX}"/bin/sh

		# Undo Solaris-based defaults pointing to /usr/xpg5/bin
		myconf+=( --disable-path-for-script )
	fi

	ECONF_SOURCE="${S}" econf "${myconf[@]}"
}

multilib_src_compile() {
	# -fprofile-partial-training because upstream note the test suite isn't super comprehensive
	# See https://documentation.suse.com/sbp/all/html/SBP-GCC-10/index.html#sec-gcc10-pgo
	local pgo_generate_flags=$(usev pgo "-fprofile-update=atomic -fprofile-dir=${T}/${ABI}-pgo -fprofile-generate=${T}/${ABI}-pgo $(test-flags-CC -fprofile-partial-training)")
	local pgo_use_flags=$(usev pgo "-fprofile-use=${T}/${ABI}-pgo -fprofile-dir=${T}/${ABI}-pgo $(test-flags-CC -fprofile-partial-training)")

	emake CFLAGS="${CFLAGS} ${pgo_generate_flags}"

	if use pgo ; then
		emake CFLAGS="${CFLAGS} ${pgo_generate_flags}" -k check

		if tc-is-clang; then
			llvm-profdata merge "${T}"/${ABI}-pgo --output="${T}"/${ABI}-pgo/default.profdata || die
		fi

		emake clean
		emake CFLAGS="${CFLAGS} ${pgo_use_flags}"
	fi
}

multilib_src_install_all() {
	find "${ED}" -type f -name '*.la' -delete || die

	if use doc ; then
		rm "${ED}"/usr/share/doc/${PF}/COPYING* || die
	fi
}

pkg_preinst() {
	preserve_old_lib /usr/$(get_libdir)/liblzma$(get_libname 0)
}

pkg_postinst() {
	preserve_old_lib_notify /usr/$(get_libdir)/liblzma$(get_libname 0)
}
