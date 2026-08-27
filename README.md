# Omasplash

Unsplash wallpapers for [Omarchy](https://omarchy.org). Browse by category or
search, click a photo to set it as your background, and let it rotate on a
timer.

## Install

```bash
omarchy plugin add https://github.com/klair/omasplash.git --enable --yes
```

Then add an Unsplash **Access Key** — create a free app at
[unsplash.com/oauth/applications](https://unsplash.com/oauth/applications) and
paste the key into the browser overlay (click the bar icon), or from a shell:

```bash
~/.config/omarchy/plugins/co.klair.omasplash/omasplash key set <access-key>
```

The key is written to `~/.config/omarchy/omasplash.key` with mode 0600 and is
handed to `curl` over stdin, so it never appears in `shell.json` or in `ps`.

## Using it

| Action | Where |
|--------|-------|
| Browse and search | Left click the bar icon |
| Apply a random photo matching the filter | Middle click, or "Surprise me" |
| Toggle rotation on/off | Right click |
| Pick a category | Topic chips in the overlay |
| Pick a rotation interval | The interval button in the overlay |

Bind the overlay to a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT", "W", "omarchy-shell shell toggle co.klair.omasplash '{}'")
```

## How it fits Omarchy

Wallpapers are not rendered by this plugin. Photos are downloaded into the
**current theme's** user background folder —
`~/.config/omarchy/backgrounds/<theme>/` — and applied with
`omarchy theme bg set`. That means they join the native per-theme pool, so
`omarchy theme bg next` and the stock background switcher cycle them too.

Only the newest `keepLast` downloads are kept. Pruning only ever touches files
named `unsplash-*.jpg`, so theme wallpapers and anything you added by hand are
left alone.

## Configuration

One file, `~/.config/omarchy/omasplash.json`, shared by the bar widget, the
overlay, and the rotation service:

| Key | Meaning |
|-----|---------|
| `topic` | Unsplash topic slug, e.g. `wallpapers`, `nature`. Ignored when `query` is set |
| `query` | Free-text search. Takes precedence over `topic` |
| `orientation` | `landscape`, `portrait`, `squarish`, or `any` |
| `contentFilter` | `high` or `low` — Unsplash's own safety filter |
| `rotateMinutes` | `0` disables rotation; otherwise minutes between changes |
| `downloadDir` | Override the download folder. Empty means the current theme's |
| `keepLast` | How many downloads to keep |
| `width` | Requested image width. `0` means the widest connected monitor |

Edit it in the overlay, or from the CLI:

```bash
omasplash config show
omasplash config set topic nature
omasplash config set rotateMinutes 60
```

Everything else the plugin does is available from the same CLI —
`omasplash help` lists it.

## Attribution

Unsplash's API terms require crediting the photographer and pinging the photo's
download endpoint whenever an image is actually used. Omasplash does both: the
grid hotlinks CDN thumbnails rather than downloading them, and only an applied
photo triggers a download event. Each downloaded file gets a
`<file>.credit.json` sidecar, and the bar tooltip names the photographer.

## Requirements

`curl`, `jq`, and `file` — all present on a stock Omarchy install.
