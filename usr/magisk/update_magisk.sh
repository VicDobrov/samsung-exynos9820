#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

ver="$(cat "$DIR/magisk_version" 2>/dev/null || echo -n 'none')"

if [ "x$1" = "xcanary" ]
then
	nver="canary"
	magisk_link="https://github.com/topjohnwu/magisk-files/raw/${nver}/app-debug.apk"
elif [ "x$1" = "xalpha" ]
then
	nver="alpha"
	magisk_link="https://github.com/vvb2060/magisk_files/raw/${nver}/app-release.apk"
else
	if [ "x$1" = "x" ]; then
		nver="$(curl -sf https://api.github.com/repos/topjohnwu/Magisk/releases/latest | grep -m1 '"tag_name"' | cut -d '"' -f4)"
	else
		nver="$1"
	fi
	dash='-'
	if [ "$nver" = "v26.3" ]; then
		dash='.'
	fi
	# Точный URL ассета берём из GitHub API — смена имён файлов в релизах больше не страшна
	magisk_link="$(curl -sf "https://api.github.com/repos/topjohnwu/Magisk/releases/tags/${nver}" \
		| grep -o '"browser_download_url": *"[^"]*\.apk"' \
		| grep -i "magisk-" | head -n1 | cut -d '"' -f4)" || true
	# Запасной вариант — старый шаблон URL
	[ -n "$magisk_link" ] || magisk_link="https://github.com/topjohnwu/Magisk/releases/download/${nver}/Magisk${dash}${nver}.apk"
fi

echo "Magisk: requested=$1 resolved=$nver"
echo "Downloading: $magisk_link"

if ! curl -fL --retry 3 --output "$DIR/magisk.zip" "$magisk_link"; then
	echo "ERROR: failed to download Magisk from $magisk_link" >&2
	exit 1
fi

echo "--- APK contents: ---"
unzip -Z1 "$DIR/magisk.zip" || true
echo "---------------------"

# Ищем нужные файлы по имени в любом месте архива,
# потому что структура APK в Magisk 31.x изменилась
init_entry="$(unzip -Z1 "$DIR/magisk.zip" | grep 'arm64-v8a/libmagiskinit\.so$' | head -n1 || true)"
[ -n "$init_entry" ] || init_entry="$(unzip -Z1 "$DIR/magisk.zip" | grep 'libmagiskinit\.so$' | head -n1 || true)"

m32_entry="$(unzip -Z1 "$DIR/magisk.zip" | grep 'armeabi-v7a/libmagisk32\.so$' | head -n1 || true)"
[ -n "$m32_entry" ] || m32_entry="$(unzip -Z1 "$DIR/magisk.zip" | grep 'libmagisk32\.so$' | head -n1 || true)"

m64_entry="$(unzip -Z1 "$DIR/magisk.zip" | grep 'arm64-v8a/libmagisk64\.so$' | head -n1 || true)"
[ -n "$m64_entry" ] || m64_entry="$(unzip -Z1 "$DIR/magisk.zip" | grep 'libmagisk64\.so$' | head -n1 || true)"

stub_entry="$(unzip -Z1 "$DIR/magisk.zip" | grep 'stub\.apk$' | head -n1 || true)"

if [ -z "$init_entry" ]; then
	echo "ERROR: libmagiskinit.so not found in APK (see listing above)." >&2
	exit 1
fi
if [ -z "$m32_entry" ] || [ -z "$m64_entry" ]; then
	echo "ERROR: libmagisk32.so / libmagisk64.so not found in APK (see listing above)." >&2
	echo "Refusing to build a boot image with broken Magisk payload." >&2
	exit 1
fi

echo "Extracting: $init_entry / $m32_entry / $m64_entry"

unzip -o -j "$DIR/magisk.zip" "$init_entry" -d "$DIR" >/dev/null
mv -f "$DIR/$(basename "$init_entry")" "$DIR/magiskinit"

unzip -o -j "$DIR/magisk.zip" "$m32_entry" -d "$DIR" >/dev/null
unzip -o -j "$DIR/magisk.zip" "$m64_entry" -d "$DIR" >/dev/null
xz --force --check=crc32 "$DIR/$(basename "$m32_entry")" "$DIR/$(basename "$m64_entry")"
mv -f "$DIR/$(basename "$m32_entry").xz" "$DIR/magisk32.xz"
mv -f "$DIR/$(basename "$m64_entry").xz" "$DIR/magisk64.xz"

if [ -n "$stub_entry" ]; then
	unzip -o -j "$DIR/magisk.zip" "$stub_entry" -d "$DIR" >/dev/null
	mv -f "$DIR/$(basename "$stub_entry")" "$DIR/stub"
	xz --force --check=crc32 "$DIR/stub"
else
	echo "WARNING: stub.apk not found in this release - hide-the-app feature is gone."
	rm -f "$DIR/stub.xz"
fi

echo -n "$nver" > "$DIR/magisk_version"
rm -f "$DIR/magisk.zip"
touch "$DIR/initramfs_list"
