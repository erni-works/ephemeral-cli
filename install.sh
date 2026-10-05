#!/bin/sh
# Install the ephemeral CLI on macOS or Linux:
#
#   curl -fsSL https://ephemer.al/install.sh | sh
#
# Environment:
#   EPHEMERAL_VERSION        release to install, e.g. v1.2.3 (default: latest)
#   EPHEMERAL_INSTALL_DIR    target directory (default: $HOME/.local/bin)
#   EPHEMERAL_DOWNLOAD_BASE  release repository URL
#                            (default: https://github.com/erni-works/ephemeral-cli)
#
# The archive is verified against the release's checksums.txt before
# anything is installed. No sudo is used; choose a writable directory.
set -eu

fail() {
	printf 'ephemeral installer: %s\n' "$*" >&2
	exit 1
}

have() {
	command -v "$1" >/dev/null 2>&1
}

# fetch URL FILE
fetch() {
	if have curl; then
		curl -fsSL --retry 3 -o "$2" "$1" || fail "could not download $1"
	else
		wget -q -O "$2" "$1" || fail "could not download $1"
	fi
}

# latest_tag BASE: read the tag from the /releases/latest redirect, which
# needs no GitHub API token and is not rate limited.
latest_tag() {
	if have curl; then
		location=$(curl -fsS -o /dev/null -w '%{redirect_url}' "$1/releases/latest") || location=
	else
		location=$(wget -S --spider "$1/releases/latest" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tr -d '\r' | grep '/releases/tag/' | head -n 1) || location=
	fi
	case $location in
	*/releases/tag/*) tag=${location##*/releases/tag/} ;;
	*) fail "could not determine the latest release from $1/releases/latest; set EPHEMERAL_VERSION" ;;
	esac
	printf '%s\n' "${tag%%[?#]*}"
}

sha256() {
	if have sha256sum; then
		sha256sum "$1" | cut -d ' ' -f 1
	elif have shasum; then
		shasum -a 256 "$1" | cut -d ' ' -f 1
	else
		fail "sha256sum or shasum is required to verify the download"
	fi
}

main() {
	base=${EPHEMERAL_DOWNLOAD_BASE:-https://github.com/erni-works/ephemeral-cli}
	base=${base%/}
	install_dir=${EPHEMERAL_INSTALL_DIR:-${HOME:?HOME is not set}/.local/bin}

	have curl || have wget || fail "curl or wget is required"
	have tar || fail "tar is required"

	case $(uname -s) in
	Linux) os=linux ;;
	Darwin) os=darwin ;;
	*) fail "unsupported operating system $(uname -s); on Windows run: irm https://ephemer.al/install.ps1 | iex" ;;
	esac
	case $(uname -m) in
	x86_64 | amd64) arch=amd64 ;;
	arm64 | aarch64) arch=arm64 ;;
	*) fail "unsupported architecture $(uname -m)" ;;
	esac
	# A shell translated by Rosetta reports x86_64 on Apple silicon.
	if [ "$os" = darwin ] && [ "$arch" = amd64 ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
		arch=arm64
	fi

	if [ -n "${EPHEMERAL_VERSION:-}" ]; then
		tag=v${EPHEMERAL_VERSION#v}
	else
		tag=$(latest_tag "$base")
	fi
	case $tag in
	v[0-9]*.[0-9]*.[0-9]*) ;;
	*) fail "invalid version '$tag'; use a version like v1.2.3" ;;
	esac
	version=${tag#v}
	archive="ephemeral_${version}_${os}_${arch}.tar.gz"

	tmp=$(mktemp -d 2>/dev/null || mktemp -d -t ephemeral)
	trap 'rm -rf "$tmp"' EXIT
	trap 'exit 1' HUP INT TERM

	printf 'Downloading ephemeral %s for %s/%s...\n' "$version" "$os" "$arch"
	fetch "$base/releases/download/$tag/checksums.txt" "$tmp/checksums.txt"
	expected=$(awk -v name="$archive" '$2 == name || $2 == "*" name { print $1; exit }' "$tmp/checksums.txt")
	[ -n "$expected" ] || fail "release $tag has no build for $os/$arch"
	fetch "$base/releases/download/$tag/$archive" "$tmp/$archive"
	actual=$(sha256 "$tmp/$archive")
	[ "$actual" = "$expected" ] || fail "checksum mismatch for $archive (expected $expected, got $actual); nothing was installed"

	mkdir "$tmp/extract"
	tar -xzf "$tmp/$archive" -C "$tmp/extract" || fail "could not extract $archive"
	[ -f "$tmp/extract/ephemeral" ] || fail "$archive does not contain the ephemeral executable"

	mkdir -p "$install_dir" || fail "could not create $install_dir; set EPHEMERAL_INSTALL_DIR to a writable directory"
	target="$install_dir/ephemeral"
	# Copy beside the target, then rename: atomic, and safe if ephemeral is running.
	cp "$tmp/extract/ephemeral" "$target.tmp.$$" || fail "could not write to $install_dir; set EPHEMERAL_INSTALL_DIR to a writable directory"
	chmod 755 "$target.tmp.$$"
	mv -f "$target.tmp.$$" "$target" || {
		rm -f "$target.tmp.$$"
		fail "could not install $target"
	}

	installed=$("$target" version) || fail "installed $target, but it does not run on this system"
	printf 'Installed %s to %s\n' "$installed" "$target"

	case ":${PATH}:" in
	*":$install_dir:"*)
		found=$(command -v ephemeral 2>/dev/null || true)
		if [ -n "$found" ] && [ "$found" != "$target" ]; then
			printf 'Note: %s comes first on your PATH; remove it or put %s before it.\n' "$found" "$install_dir"
		fi
		;;
	*)
		# shellcheck disable=SC2016 # $PATH is printed for the user to paste.
		printf '\n%s is not on your PATH. Add it, e.g. in ~/.profile or your shell rc file:\n  export PATH="%s:$PATH"\n' "$install_dir" "$install_dir"
		;;
	esac
	printf '\nGet started: ephemeral login\n'
}

main "$@"
