[![test](https://github.com/unfrgivn/rex-ladybird/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/unfrgivn/rex-ladybird/actions/workflows/test.yml)

# rex-ladybird

A Rex plugin with two actions:

- **Open Ladybird** opens a Ladybird terminal browser in a new window.
- **Open Ladybird Floating** opens the same browser in a floating layer over the
  active window.

Both actions appear in Rex's command palette under **Ladybird**. Search for
`ladyb`.

Ladybird has a headless terminal mode that paints pages with the Kitty graphics
protocol and turns terminal mouse, keyboard, paste and focus reports back into
page input. Rex already provides a capable terminal, so this plugin launches
Ladybird in a normal Rex block and gets out of the way.

```
Rex client
  ^ Kitty graphics and input
  |
Rex server terminal block
  ^ frames and key reports
  |
Ladybird --headless=terminal
```

## Requirements

- Rex Beta with Kitty graphics support. Rex preview.20 and later is known to
  work.
- A Ladybird build with `--headless=terminal`. That mode landed on
  2026-11-09 in
  [Ladybird PR #14186](https://github.com/LadybirdBrowser/ladybird/pull/14186).
- macOS or Linux.

Check the two moving parts on the machine that runs Rex:

```sh
rex version
/Applications/Ladybird.app/Contents/MacOS/Ladybird --help | grep headless
```

## Install

Clone the plugin somewhere permanent, then run the installer:

```sh
git clone https://github.com/unfrgivn/rex-ladybird.git ~/Sites/rex-ladybird
~/Sites/rex-ladybird/install.sh
```

The installer links the checkout into
`~/.config/rex/plugins/rex-ladybird` and adds this line to
`~/.config/rex/init.lua`:

```lua
require("plugins.rex-ladybird").setup()
```

It checks the config before reloading it. If `rex` is not on your `PATH`, the
installer finds the copy inside Rex Beta. You can also point it at a CLI
explicitly:

```sh
REX_BIN="/path/to/rex" ~/Sites/rex-ladybird/install.sh
```

If you use a non-default config file, the installer respects `REX_CONFIG`:

```sh
REX_CONFIG="/path/to/init.lua" ~/Sites/rex-ladybird/install.sh
```

Run the installer again after `git pull`. It is safe to repeat.

## Use

Open the command palette and search for `ladyb`, or use the default keys:

| Binding | Action |
| --- | --- |
| `Cmd+Shift+L` | Open Ladybird |
| `Cmd+Shift+Alt+L` | Open Ladybird Floating |

You can change either binding from the command palette with `Cmd+Enter`.

Inside the browser:

| Key | Action |
| --- | --- |
| `Ctrl+L` | Focus the URL prompt |
| `Ctrl+R` or `F5` | Reload |
| `Alt+Left` / `Alt+Right` | Back and forward |
| `Ctrl+Q` | Quit and close the browser block |

Mouse clicks, scrolling, text selection, keyboard input and bracketed paste are
forwarded to the page.

## Configure

Call `setup` with any options you need:

```lua
require("plugins.rex-ladybird").setup{
  binary = "/Applications/Ladybird.app/Contents/MacOS/Ladybird",
  device_pixel_ratio = "auto",
  extra_args = { "--enable-autoplay" },
  keep_open = false,
  float_bounds = { 0.1, 0.1, 0.8, 0.75 },
}
```

| Option | Default | Meaning |
| --- | --- | --- |
| `binary` | auto | Ladybird binary or `.app` path. `LADYBIRD_BIN` also works. |
| `device_pixel_ratio` | `"auto"` | Number, or `"auto"` to guess from the focused terminal's cell height. |
| `extra_args` | `{}` | Extra Ladybird arguments, added before the URL. |
| `bind` | `true` | Register the default keybindings. |
| `keep_open` | `false` | Keep the block open after Ladybird exits. |
| `label` | `"ladybird"` | The block label used by the plugin. |
| `float_bounds` | `{0.1, 0.1, 0.8, 0.75}` | Floating layer rectangle as `{x, y, width, height}` fractions of the window. |

To keep a separate Ladybird profile, pass a profile path:

```lua
require("plugins.rex-ladybird").setup{
  extra_args = {
    "--profile-path",
    os.getenv("HOME") .. "/.local/share/ladybird-rex",
  },
}
```

A path avoids sharing cookies and history with a desktop Ladybird, and avoids
relying on named profile creation in headless mode.

The pixel ratio guess uses `2` when the focused terminal reports a cell height
of at least 24 pixels, otherwise `1`. That covers a common Retina and non-Retina
setup, but it is still a guess. If pages look too small or too large, pin it:

```lua
require("plugins.rex-ladybird").setup{ device_pixel_ratio = 2 }
```

`float_bounds` must fit inside the window: `x + width <= 1` and
`y + height <= 1`.

## CLI

The actions work from `rex do` too:

```sh
rex do ladybird_open url=https://example.com
rex do ladybird_float url=example.com
```

## Troubleshooting

**The block opens but the page is blank.** Run Ladybird directly in a Rex
terminal to separate Rex and Ladybird:

```sh
/Applications/Ladybird.app/Contents/MacOS/Ladybird --headless=terminal https://example.com
```

If that is also blank, check `/tmp/ladybird-terminal-*.log`. Update Rex and
Ladybird. Kitty graphics and temporary-file image transmission are the moving
parts.

**Ladybird was not found.** Set the path explicitly in `setup`, or:

```sh
LADYBIRD_BIN=/path/to/Ladybird rex config reload
```

The environment of the Rex server matters, not the environment of the shell
that ran `rex config reload`.

**The page is tiny or oversized.** Set `device_pixel_ratio` to `1` or `2`.

**The floating bounds are rejected.** Use four fractions, keep positive width
and height, and leave `x + width` and `y + height` at or below `1`.

**A remote Rex server cannot start it.** Ladybird must be installed on the
machine running the Rex server, not on the machine running the Rex client.

**`Ctrl+Q` does nothing.** Click the browser block first. Rex sends keys to the
focused block.

## Uninstall

```sh
rm ~/.config/rex/plugins/rex-ladybird
rex config reload
```

Then remove the `require("plugins.rex-ladybird").setup()` line from
`~/.config/rex/init.lua`.

## Development

The plugin is a plain Lua module, so the loop is short:

```sh
rex config check
rex config reload
rex keymap | grep ladybird
```

Run the tests:

```sh
lua5.1 test/init.test.lua
sh test/install.test.sh
shellcheck install.sh test/install.test.sh
```

If Lua is not installed, Rex's own Lua VM can run the unit test:

```sh
rex do test/init.test.lua
```

The installer uses a symlink, so edits to `init.lua` take effect after
`rex config reload`.

The repository also has a `rex-plugin.toml`, so it can be installed with
[rexd](https://github.com/tornikegomareli/rexd) if you use that:

```sh
rexd install ./rex-ladybird --link
```

## Security

The plugin starts a normal Ladybird process as your user. It does not open a
port or add a remote control channel. Web content gets whatever sandboxing
Ladybird provides.

## License

MIT. See [LICENSE](LICENSE).
