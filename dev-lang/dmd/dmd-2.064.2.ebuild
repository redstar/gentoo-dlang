# Copyright 1999-2013 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI="5"

inherit eutils multilib-build

DESCRIPTION="Reference compiler for the D programming language"
HOMEPAGE="http://dlang.org/"
SRC_URI="http://downloads.dlang.org.s3.amazonaws.com/releases/2013/${PN}.${PV}.zip"

# DMD supports amd64/x86 exclusively
KEYWORDS="amd64 x86"
SLOT="2.064"
IUSE="doc examples"

# License doesn't allow redistribution
LICENSE="DMD"
RESTRICT="mirror"

CURL_DEPEND="
	!amd64? ( net-misc/curl )
	amd64? (
		abi_x86_64? ( net-misc/curl )
		abi_x86_32? ( app-emulation/emul-linux-x86-baselibs )
	)"

DEPEND="
	${CURL_DEPEND}
	app-arch/unzip
	app-admin/eselect-dlang
	"
RDEPEND="
	${CURL_DEPEND}
	!dev-lang/dmd-bin
	"

S="${WORKDIR}/dmd2"

PREFIX="opt/${PN}-${SLOT}"
IMPORT_DIR="/${PREFIX}/import"

src_prepare() {
	# Remove precompiled binaries and non-essential files.
	rm -r README.TXT windows osx linux || die "Failed to remove included binaries."

	# convert line-endings of file-types that start as cr-lf and are patched or installed later on
	for file in $( find . -name "*.txt" -o -name "*.html" -o -name "*.d" -o -name "*.di" -o -name "*.ddoc" -type f ); do
		edos2unix $file || die "Failed to convert DOS line-endings to Unix."
	done

	# patch: copy VERSION file into dmd directory
	cp src/VERSION src/dmd/VERSION || die "Failed to copy VERSION file into dmd directory."

	# Rename man pages to reflect slot number.
	mkdir man/man5 || die "Failed to create man/man5."
	mv man/man1/dmd.conf.5 man/man5/dmd.conf.5

	# Write a simple dmd.conf to bootstrap druntime and phobos
	cat > src/dmd/dmd.conf << EOF
[Environment]
DFLAGS=-L--export-dynamic
EOF

	# Copy missing LICENSE_1_0.txt
	cp "${FILESDIR}/LICENSE_1_0.txt" src/phobos/ || die "Couldn't copy LICENSE_1_0.txt"

	# Allow installation into lib32/lib64
	epatch "${FILESDIR}/${SLOT}-makefile-multilib.patch"
}

abi_to_model() {
	[[ "${ABI:0:5}" == "amd64" ]] && echo 64 || echo 32
}

dmd_foreach_abi() {
	for ABI in $(multilib_get_enabled_abis); do
		local MODEL=$(abi_to_model)
		einfo "Executing ${1} in ${MODEL}-bit ..."
		"${@}"
	done
}

src_compile() {
	# A native build of dmd is used to compile the runtimes for both x86 and amd64
	# We cannot use multilib-minimal yet, as we have to be sure dmd for amd64
	# always gets build first.
	einfo "Building ${PN}..."
	emake -C src/dmd -f posix.mak TARGET_CPU=X86 RELEASE=1

	compile_libraries() {
		einfo 'Building druntime...'
		emake -C src/druntime -f posix.mak MODEL=${MODEL} DMD=../dmd/dmd

		einfo 'Building Phobos 2...'
		emake -C src/phobos -f posix.mak MODEL=${MODEL} DMD=../dmd/dmd
	}

	dmd_foreach_abi compile_libraries
}

src_test() {
	test_hello_world() {
		src/dmd/dmd -m${MODEL} -Isrc/phobos -Isrc/druntime/import -L-Lsrc/phobos/generated/linux/release/${MODEL} samples/d/hello.d || die "Failed to build hello.d (${MODEL}-bit)"
		./hello ${MODEL}-bit || die "Failed to run test sample (${MODEL}-bit)"
		rm hello.o hello
	}

	dmd_foreach_abi test_hello_world
}

src_install() {
	# Prepeare and install config file.
	if has_multilib_profile; then
		cat > src/dmd/dmd.conf.default << EOF
[Environment32]
DFLAGS=-I${IMPORT_DIR} -L-L/${PREFIX}/lib32 -L-rpath -L/${PREFIX}/lib32 -L--export-dynamic
[Environment64]
DFLAGS=-I${IMPORT_DIR} -L-L/${PREFIX}/lib64 -L-rpath -L/${PREFIX}/lib64 -L--export-dynamic
EOF
	else
		cat > src/dmd/dmd.conf.default << EOF
[Environment]
DFLAGS=-I${IMPORT_DIR} -L-L/${PREFIX}/lib -L-rpath -L/${PREFIX}/lib -L--export-dynamic
EOF
	fi
	einfo "Installing ${PN}..."
	emake -C src/dmd -f posix.mak TARGET_CPU=X86 RELEASE=1 INSTALL_DIR="${D}${PREFIX}" install

	einfo 'Installing druntime...'
	install_druntime() {
		emake -C src/druntime -f posix.mak INSTALL_DIR="${D}${PREFIX}" LIB_DIR="$(get_libdir)" MODEL=$(abi_to_model) install
		rm -r "${D}${PREFIX}/html" || die "Couldn't remove duplicate HTML documentation."
	}
	dmd_foreach_abi install_druntime

	einfo 'Installing Phobos 2...'
	into ${PREFIX}
	install_library() {
		emake -C src/phobos -f posix.mak INSTALL_DIR="${D}${PREFIX}" LIB_DIR="$(get_libdir)" MODEL=$(abi_to_model) install
		dolib.so src/phobos/generated/linux/release/${MODEL}/libphobos2.so.0.64.0
		dosym libphobos2.so.0.64.0 ${PREFIX}/$(get_libdir)/libphobos2.so.0.64
		dosym libphobos2.so.0.64.0 ${PREFIX}/$(get_libdir)/libphobos2.so
	}
	dmd_foreach_abi install_library

	# man pages, docs and samples
	insinto ${PREFIX}/man/man1
	doins man/man1/dmd.1
	insinto ${PREFIX}/man/man5
	doins man/man5/dmd.conf.5
	insinto ${PREFIX}
	use doc && doins -r html
	if use examples; then
		docompress -x ${PREFIX}/samples/
		insinto ${PREFIX}/samples
		doins -r samples/d/*
	fi
}

pkg_postinst() {
	elog "License files are in: /${PREFIX}"
	use examples && elog "Examples can be found in: /${PREFIX}/samples"
	use doc && elog "HTML documentation is in: /${PREFIX}/html"
}
