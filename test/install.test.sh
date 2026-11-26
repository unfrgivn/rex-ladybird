#!/bin/sh
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home"

run_install() {
    HOME="$tmp/home" \
    XDG_CONFIG_HOME="$tmp/home/.config" \
    REX_BIN=/usr/bin/true \
    sh "$here/install.sh" >/dev/null
}

run_install

init="$tmp/home/.config/rex/init.lua"
plugin="$tmp/home/.config/rex/plugins/rex-ladybird"

[ -f "$init" ] || {
    echo "missing $init" >&2
    exit 1
}
grep -Fq 'require("plugins.rex-ladybird").setup()' "$init" || {
    echo "missing require line in $init" >&2
    exit 1
}
[ -h "$plugin" ] || {
    echo "missing plugin symlink at $plugin" >&2
    exit 1
}
[ "$(readlink "$plugin")" = "$here" ] || {
    echo "plugin symlink points at the wrong directory" >&2
    exit 1
}

run_install

count=$(grep -Fc 'require("plugins.rex-ladybird")' "$init")
[ "$count" -eq 1 ] || {
    echo "installer added the require line $count times" >&2
    exit 1
}

# REX_CONFIG should move both the init file and the plugin install.
custom="$tmp/custom/rex.lua"
HOME="$tmp/home" REX_CONFIG="$custom" REX_BIN=/usr/bin/true sh "$here/install.sh" >/dev/null
[ -f "$custom" ] || {
    echo "missing $custom" >&2
    exit 1
}
grep -Fq 'require("plugins.rex-ladybird").setup()' "$custom" || {
    echo "missing require line in $custom" >&2
    exit 1
}
[ -h "$tmp/custom/plugins/rex-ladybird" ] || {
    echo "missing plugin symlink beside $custom" >&2
    exit 1
}

echo "install ok"
