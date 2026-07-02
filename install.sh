#!/bin/sh
# Install the vim-herdr-navigator helper binary into <plugin>/bin.
#
# Designed to run as a plugin-manager build hook (lazy.nvim `build`,
# vim-plug `do`, ...), with the plugin checkout as the working directory.
# It downloads the prebuilt binary from the GitHub release matching the
# checked-out plugin version, so the helper and plugin stay in lockstep.
# When no prebuilt matches (or downloads fail), it builds from the source
# already present in this checkout with cargo.
#
# Environment:
#   VIM_HERDR_NAVIGATOR_NO_LOCAL_BIN=1  don't copy into ~/.local/bin
#   VIM_HERDR_NAVIGATOR_FORCE_BUILD=1   skip the download, build with cargo
set -eu

REPO="AVGVSTVS96/vim-herdr-navigator"
NAME="vim-herdr-navigator"

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
BIN_DIR="$SCRIPT_DIR/bin"
BIN="$BIN_DIR/$NAME"

say() { printf '%s\n' "$NAME: $*"; }
warn() { printf '%s\n' "$NAME: warning: $*" >&2; }
fail() {
  printf '%s\n' "$NAME: error: $*" >&2
  exit 1
}

version() {
  # First `version = "..."` in the helper's manifest is the package version.
  sed -n 's/^version = "\(.*\)"/\1/p' "$SCRIPT_DIR/helper/Cargo.toml" | head -n 1
}

target_triple() {
  os=$(uname -s)
  arch=$(uname -m)
  case "$os" in
    Darwin)
      case "$arch" in
        arm64 | aarch64) echo "aarch64-apple-darwin" ;;
        x86_64) echo "x86_64-apple-darwin" ;;
        *) return 1 ;;
      esac
      ;;
    Linux)
      case "$arch" in
        arm64 | aarch64) echo "aarch64-unknown-linux-musl" ;;
        x86_64 | amd64) echo "x86_64-unknown-linux-musl" ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

fetch() {
  # fetch <url> <dest>; fails quietly so callers can fall back.
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    return 1
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
  else
    return 1
  fi
}

install_from_release() {
  ver="$1"
  triple=$(target_triple) || {
    warn "no prebuilt binary for $(uname -s)/$(uname -m)"
    return 1
  }

  asset="$NAME-$triple.tar.xz"
  url="https://github.com/$REPO/releases/download/v$ver/$asset"

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  say "downloading $asset (v$ver)..."
  fetch "$url" "$tmp/$asset" || {
    warn "download failed: $url"
    return 1
  }

  # Verify against the .sha256 companion the release publishes. A missing
  # checksum file only warns; a mismatched checksum is a hard failure.
  if fetch "$url.sha256" "$tmp/$asset.sha256"; then
    want=$(cut -d ' ' -f 1 <"$tmp/$asset.sha256")
    got=$(sha256_of "$tmp/$asset") || warn "no sha256 tool; skipping checksum"
    if [ -n "${got:-}" ] && [ "$want" != "$got" ]; then
      fail "checksum mismatch for $asset (expected $want, got $got)"
    fi
  else
    warn "checksum file unavailable; skipping verification"
  fi

  tar -xf "$tmp/$asset" -C "$tmp" || {
    warn "could not extract $asset"
    return 1
  }
  extracted=$(find "$tmp" -type f -name "$NAME" | head -n 1)
  if [ -z "$extracted" ]; then
    warn "binary not found inside $asset"
    return 1
  fi

  mkdir -p "$BIN_DIR"
  cp "$extracted" "$BIN"
  chmod +x "$BIN"
}

install_from_source() {
  command -v cargo >/dev/null 2>&1 || return 1
  say "building from source with cargo (this can take a minute)..."
  # Explicit || return: callers invoke this in a `||` list, which suppresses
  # `set -e` for the whole function body — an unchecked build failure would
  # fall through and copy a stale binary from an earlier build.
  (cd "$SCRIPT_DIR" && cargo build --release --package "$NAME") || return 1
  mkdir -p "$BIN_DIR"
  cp "$SCRIPT_DIR/target/release/$NAME" "$BIN"
}

install_into_path() {
  # Herdr keybindings spawn the helper by name, so expose it on PATH via
  # ~/.local/bin. A real copy, not a symlink into the plugin dir: uninstalling
  # the plugin then leaves a working binary instead of a dangling link.
  [ "${VIM_HERDR_NAVIGATOR_NO_LOCAL_BIN:-}" = "1" ] && return 0
  ver="$1"
  dest="$HOME/.local/bin/$NAME"

  # Also replace symlinks (e.g. from a hand-rolled `ln -s` into the plugin
  # dir) even when they report the right version: a real copy must survive
  # plugin uninstall.
  if [ -L "$dest" ] || [ "$("$dest" --version 2>/dev/null)" != "$NAME $ver" ]; then
    mkdir -p "$HOME/.local/bin"
    # Write-then-rename so we never overwrite a binary Herdr may be running.
    cp "$BIN" "$dest.tmp.$$"
    chmod +x "$dest.tmp.$$"
    mv -f "$dest.tmp.$$" "$dest"
  fi

  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "\$HOME/.local/bin is not on your PATH; add it so Herdr can find $NAME" ;;
  esac

  # A stale copy elsewhere on PATH (e.g. an old cargo install in ~/.cargo/bin)
  # would shadow this one for Herdr while Neovim uses the plugin-local binary.
  resolved=$(command -v "$NAME" 2>/dev/null || true)
  if [ -n "$resolved" ] && [ "$resolved" != "$dest" ]; then
    resolved_ver=$("$resolved" --version 2>/dev/null || echo "unknown version")
    if [ "$resolved_ver" != "$NAME $ver" ]; then
      warn "PATH resolves $NAME to $resolved ($resolved_ver), which shadows the installed v$ver; remove it or reorder PATH"
    fi
  fi
}

main() {
  ver=$(version)
  [ -n "$ver" ] || fail "could not read version from helper/Cargo.toml"

  # Already have this exact version? Nothing to do.
  if [ -x "$BIN" ] && [ "$("$BIN" --version 2>/dev/null)" = "$NAME $ver" ]; then
    say "v$ver already installed at $BIN"
    install_into_path "$ver"
    return 0
  fi

  if [ "${VIM_HERDR_NAVIGATOR_FORCE_BUILD:-}" = "1" ]; then
    install_from_source || fail "source build failed (is Rust installed? https://rustup.rs)"
  else
    install_from_release "$ver" || {
      warn "falling back to building from source"
      install_from_source || fail "no prebuilt binary and the source build failed.
  Install Rust (https://rustup.rs) and re-run, or download a release manually:
  https://github.com/$REPO/releases"
    }
  fi

  install_into_path "$ver"
  say "installed $("$BIN" --version) at $BIN"
}

main
