#!/bin/sh
set -eu

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Usage: ./install.sh

Links this checkout into Rex's config, adds the require line, checks the
config, and reloads Rex when it is running.

Environment:
  REX_BIN          path to the rex CLI when it is not on PATH
  REX_CONFIG       path to a non-default Rex init.lua
  XDG_CONFIG_HOME  overrides ~/.config
EOF
    exit 0
    ;;
esac

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

if [ -n "${REX_CONFIG:-}" ]; then
  init=$REX_CONFIG
  config_dir=$(dirname -- "$init")
else
  config_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/rex
  init="$config_dir/init.lua"
fi

mkdir -p "$config_dir/plugins"
config_dir=$(CDPATH='' cd -- "$config_dir" && pwd)
init="$config_dir/$(basename -- "$init")"
plugins_dir="$config_dir/plugins"
plugin_link="$plugins_dir/rex-ladybird"
old_module="$config_dir/rex-ladybird.lua"

if [ -h "$plugin_link" ] && [ "$(readlink "$plugin_link")" = "$here" ]; then
  :
elif [ -e "$plugin_link" ] || [ -h "$plugin_link" ]; then
  echo "Refusing to overwrite $plugin_link. Move it aside and run again." >&2
  exit 1
fi
ln -sfn "$here" "$plugin_link"

# Remove the flat module the first version of this installer linked.
if [ -h "$old_module" ] && [ "$(readlink "$old_module")" = "$here/lua/rex-ladybird.lua" ]; then
  rm -f "$old_module"
fi

backup=
if [ -e "$init" ]; then
  backup="$init.rex-ladybird.bak"
  cp "$init" "$backup"
fi

if [ ! -e "$init" ]; then
  printf 'require("plugins.rex-ladybird").setup()\n' > "$init"
else
  if grep -Fq 'require("rex-ladybird")' "$init"; then
    tmp="$init.tmp.$$"
    sed 's|require("rex-ladybird")|require("plugins.rex-ladybird")|g' "$init" > "$tmp"
    mv "$tmp" "$init"
  fi
  if ! grep -Fq 'require("plugins.rex-ladybird")' "$init"; then
    printf '\nrequire("plugins.rex-ladybird").setup()\n' >> "$init"
  fi
fi

rex_bin=${REX_BIN:-}
if [ -z "$rex_bin" ]; then
  if command -v rex >/dev/null 2>&1; then
    rex_bin=$(command -v rex)
  elif [ -x "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex" ]; then
    rex_bin="$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
  fi
fi

if [ -n "$rex_bin" ]; then
  if ! "$rex_bin" config check; then
    if [ -n "$backup" ]; then
      mv "$backup" "$init"
      echo "Rex rejected the config. Restored $init." >&2
    else
      rm -f "$init"
      echo "Rex rejected the config. Removed the new $init." >&2
    fi
    exit 1
  fi
  rm -f "$backup"
  if ! "$rex_bin" config reload; then
    echo "Rex is not running. Start it, then run: rex config reload" >&2
  fi
else
  [ -n "$backup" ] && rm -f "$backup"
  echo "rex was not found. Start Rex and reload its config after installing." >&2
fi

echo "Installed rex-ladybird in $plugin_link"
echo "Open the command palette and search for ladyb."
