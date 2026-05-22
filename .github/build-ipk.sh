#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 Tianling Shen <cnsztl@immortalwrt.org>

set -o errexit
set -o pipefail

PKG_MGR="${1:-apk}"
RELEASE_TYPE="${2:-snapshot}"

export PKG_SOURCE_DATE_EPOCH="$(date "+%s")"
export SOURCE_DATE_EPOCH="$PKG_SOURCE_DATE_EPOCH"

BASE_DIR="$(cd "$(dirname $0)"; pwd)"
PKG_DIR="$BASE_DIR/.."

function get_mk_value() {
	awk -F "$1:=" '{print $2}' "$PKG_DIR/Makefile" | xargs
}

PKG_NAME="$(get_mk_value "PKG_NAME")"
if [ "$RELEASE_TYPE" == "release" ]; then
	PKG_VERSION="$(get_mk_value "PKG_VERSION")"
else
	PKG_VERSION="$PKG_SOURCE_DATE_EPOCH~$(git rev-parse --short HEAD)"
fi

TEMP_DIR="$(mktemp -d -p $BASE_DIR)"
TEMP_PKG_DIR="$TEMP_DIR/$PKG_NAME"
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_PKG_DIR/lib/upgrade/keep.d/"
mkdir -p "$TEMP_PKG_DIR/usr/lib/lua/luci/i18n/"
mkdir -p "$TEMP_PKG_DIR/www/"
if [ "$PKG_MGR" == "apk" ]; then
	mkdir -p "$TEMP_PKG_DIR/lib/apk/packages/"
else
	mkdir -p "$TEMP_PKG_DIR/CONTROL/"
fi

cp -fpR "$PKG_DIR/htdocs"/* "$TEMP_PKG_DIR/www/"
cp -fpR "$PKG_DIR/root"/* "$TEMP_PKG_DIR/"

cat > "$TEMP_PKG_DIR/lib/upgrade/keep.d/$PKG_NAME" <<-EOF
/etc/hongshuyun/certs/
/etc/hongshuyun/ruleset/
/etc/hongshuyun/resources/direct_list.txt
/etc/hongshuyun/resources/proxy_list.txt
EOF

po2lmo "$PKG_DIR/po/zh_Hans/hongshuyun.po" "$TEMP_PKG_DIR/usr/lib/lua/luci/i18n/hongshuyun.zh-cn.lmo"

if [ "$PKG_MGR" == "apk" ]; then
	find "$TEMP_PKG_DIR" -type f,l -printf '/%P\n' | sort > "$TEMP_PKG_DIR/lib/apk/packages/$PKG_NAME.list"
	: > "$TEMP_PKG_DIR/lib/apk/packages/$PKG_NAME.conffiles"
	: > "$TEMP_PKG_DIR/lib/apk/packages/$PKG_NAME.conffiles_static"

	echo -e '#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="'"$PKG_NAME"'"
add_group_and_user
default_postinst
[ -n "${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	killall -HUP rpcd 2>/dev/null
	exit 0
}' > "$TEMP_DIR/post-install"

	echo -e '#!/bin/sh
export PKG_UPGRADE=1
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="'"$PKG_NAME"'"
add_group_and_user
default_postinst
[ -n "${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	killall -HUP rpcd 2>/dev/null
	exit 0
}' > "$TEMP_DIR/post-upgrade"

	echo -e '#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="'"$PKG_NAME"'"
default_prerm' > "$TEMP_DIR/pre-deinstall"

	apk mkpkg \
		--info "name:$PKG_NAME" \
		--info "version:$PKG_VERSION" \
		--info "description:红薯云代理平台" \
		--info "arch:all" \
		--info "origin:https://github.com/xybingbing/luci-app-hongshuyun" \
		--info "url:" \
		--info "maintainer:Tianling Shen <cnsztl@immortalwrt.org>" \
		--info "provides:" \
		--script "post-install:$TEMP_DIR/post-install" \
		--script "post-upgrade:$TEMP_DIR/post-upgrade" \
		--script "pre-deinstall:$TEMP_DIR/pre-deinstall" \
		--info "depends:libc sing-box firewall4 kmod-nft-tproxy ucode-mod-digest" \
		--files "$TEMP_PKG_DIR" \
		--output "$TEMP_DIR/${PKG_NAME}_${PKG_VERSION}.apk"

	mv "$TEMP_DIR/${PKG_NAME}_${PKG_VERSION}.apk" "$BASE_DIR/${PKG_NAME}_${PKG_VERSION}_all.apk"
else
	mkdir -p "$TEMP_PKG_DIR/CONTROL/"

	cat > "$TEMP_PKG_DIR/CONTROL/control" <<-EOF
		Package: $PKG_NAME
		Version: $PKG_VERSION
		Depends: libc, sing-box, firewall4, kmod-nft-tproxy, ucode-mod-digest
		Source: https://github.com/xybingbing/luci-app-hongshuyun
		SourceName: $PKG_NAME
		Section: luci
		SourceDateEpoch: $PKG_SOURCE_DATE_EPOCH
		Maintainer: Tianling Shen <cnsztl@immortalwrt.org>
		Architecture: all
		Installed-Size: TO-BE-FILLED-BY-IPKG-BUILD
		Description:  红薯云代理平台
	EOF
	chmod 0644 "$TEMP_PKG_DIR/CONTROL/control"
	: > "$TEMP_PKG_DIR/CONTROL/conffiles"

	echo -e '#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_postinst $0 $@' > "$TEMP_PKG_DIR/CONTROL/postinst"
	chmod 0755 "$TEMP_PKG_DIR/CONTROL/postinst"

	cat > "$TEMP_PKG_DIR/CONTROL/postinst-pkg" <<-EOF
		[ -n "\${IPKG_INSTROOT}" ] || {
			(. /etc/uci-defaults/$PKG_NAME) && rm -f /etc/uci-defaults/$PKG_NAME
			rm -f /tmp/luci-indexcache
			rm -rf /tmp/luci-modulecache/
			exit 0
		}
	EOF
	chmod 0755 "$TEMP_PKG_DIR/CONTROL/postinst-pkg"

	echo -e '#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_prerm $0 $@' > "$TEMP_PKG_DIR/CONTROL/prerm"
	chmod 0755 "$TEMP_PKG_DIR/CONTROL/prerm"

	ipkg-build -m "" "$TEMP_PKG_DIR" "$TEMP_DIR"

	IPK_PATH="$TEMP_DIR/${PKG_NAME}_${PKG_VERSION}_all.ipk"
	AR_LIST="$(ar t "$IPK_PATH" 2>/dev/null || true)"
	if [ -z "$AR_LIST" ]; then
		REPACK_DIR="$TEMP_DIR/.repack"
		mkdir -p "$REPACK_DIR"
		if gzip -dc "$IPK_PATH" 2>/dev/null | tar -C "$REPACK_DIR" -xf - 2>/dev/null; then
			if [ -f "$REPACK_DIR/debian-binary" ] && [ -f "$REPACK_DIR/control.tar.gz" ] && [ -f "$REPACK_DIR/data.tar.gz" ]; then
				AR_IPK="$TEMP_DIR/.repacked.ipk"
				rm -f "$AR_IPK"
				( cd "$REPACK_DIR" && ar rcs "$AR_IPK" debian-binary control.tar.gz data.tar.gz )
				mv -f "$AR_IPK" "$IPK_PATH"
				AR_LIST="$(ar t "$IPK_PATH" 2>/dev/null || true)"
			fi
		fi
	fi
	if [ -z "$AR_LIST" ]; then
		echo "Invalid ipk: $IPK_PATH" >&2
		exit 1
	fi
	for f in debian-binary control.tar.gz data.tar.gz; do
		echo "$AR_LIST" | grep -qx "$f" || {
			echo "Invalid ipk: missing $f" >&2
			exit 1
		}
	done

	mv "$IPK_PATH" "$BASE_DIR/${PKG_NAME}_${PKG_VERSION}_all.ipk"
fi
