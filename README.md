# hinhnen

the name comes from Vietnamese *hình nền* (`/hïŋ˨˩ nen˨˩/`) mean wallpaper.

a small wallpaper daemon i wrote for my Hyprland / Wayland setup.

auto rotate wallpapers like Windows Spotlight or macOS's dynamic wallpapers do.


## how it works

```
source  →  cache  →  setter
   ↑
trigger
```

- **source** - where images come from
- **trigger** - when the wallpaper changes
- **setter** - how the wallpaper is applied: always with [`awww`](https://codeberg.org/LGFae/awww). if `awww-daemon` isn't running yet, hinhnen starts it for you
- **cache** - downloaded images are kept on disk

## install

```bash
curl -fsSL https://raw.githubusercontent.com/doannc2212/hinhnen/main/install.sh | sh
```

if you'd rather build from source, please install `awww` first, then run:

```bash
cargo install --path .
```

or build it manually:

```bash
cargo build --release
cp target/release/hinhnen ~/.local/bin/
```

## usage

```bash
hinhnen daemon         # start the daemon in the foreground
hinhnen next           # change the wallpaper now
hinhnen history        # show recent wallpapers
hinhnen clean          # clear cached images and history, keeping the current wallpaper
```

## config

hinhnen reads config from `~/.config/hinhnen/config.toml`.

after editing the config, you can run `hinhnen reload` and the daemon will reload your config changes.

---

### daemon

this section controls when the wallpaper changes on its own.

```toml
[daemon]
interval_secs = 1800    # how often to rotate, in seconds (1800 = 30 minutes)
change_on_login = true  # change when you log in
change_on_unlock = true # change when you unlock your screen
# on_change = "wallust run %w"  # shell command to run after every change
```

#### hooks


| hook | runs when | placeholder |
|------|-----------|-------------|
| `on_change` | after every wallpaper change | `%w` = new wallpaper path |
| `on_start` | when the daemon starts | `%w` = last wallpaper from history |
| `on_error` | an change fails | `%e` = the error message |

every `%w` (or `%e`) in your command is replaced with its value before the shell sees it.

```toml
[daemon]
on_start = "wallust run %w"
on_change = "wallust run %w"
on_error = "notify-send -u critical 'hinhnen' '%e'"
# on_change = "matugen image %w"
```

---

### setter

hinhnen will spawn `awww-daemon` if it isn't running.

setter support awww transition settings

```toml
[setter]
transition = "fade"        # transition effect
transition_duration = 1.5  # in seconds
```

`transition` is passed directly to `awww img --transition-type`. supported types:

`none` `simple` `fade` `left` `right` `top` `bottom` `wipe` `wave` `grow` `center` `any` `outer` `random`

the list can differ between awww versions, so `awww img --help` is the best way to check what yours supports.

---

### sources

each source is a `[[sources.list]]` block. hinhnen doesn't support mixing the two (more on that [below](#source-type-and-next-behaviour)).

```toml
[sources]
rotation = "weighted_random"  # weighted_random | round_robin
```

`rotation` decides how hinhnen picks a source each time the wallpaper changes:

- **`weighted_random`** - picks a source at random, favouring sources with a higher `weight`. for example, with one source at weight 2 and another at weight 1, the first is chosen about 67% of the time. the order in the file doesn't matter.
- **`round_robin`** - goes through your sources in the order they appear in the file, top to bottom. `weight` is ignored in this mode.

if a source fails for any reason (the network is down, a folder is empty, an api returns an error), hinhnen logs a warning and tries the next one. so adding more than one source also gives you a fallback.

#### local folder

uses images from a folder on your machine:

```toml
[[sources.list]]
type = "local"
path = "~/Pictures/Wallpapers"
order = "random"     # random | sequential
weight = 2
```

#### bing daily

bing's photo of the day. it's downloaded and cached, so it keeps working offline:

```toml
[[sources.list]]
type = "bing"
weight = 1
```

#### unsplash

random photos from unsplash. you'll need a free api key from [unsplash.com/developers](https://unsplash.com/developers).

```toml
[[sources.list]]
type = "unsplash"
api_key = "your_api_key_here"
query = "nature"          # optional - narrows the search
orientation = "landscape" # optional - landscape | portrait | squarish
weight = 1
```

#### nasa apod

nasa's astronomy picture of the day. you can get a free api key at [api.nasa.gov](https://api.nasa.gov).

```toml
[[sources.list]]
type = "nasa_apod"
api_key = "your_api_key_here"
weight = 1
```

#### wallhaven

random wallpapers from [wallhaven.cc](https://wallhaven.cc). you only need an api key if you want nsfw results.

```toml
[[sources.list]]
type = "wallhaven"
api_key = "your_api_key_here"  # optional - only needed for nsfw purity
query = "landscape"            # optional - search terms
categories = "111"             # optional - general/anime/people as on/off bits
purity = "100"                 # optional - sfw/sketchy/nsfw as on/off bits
weight = 1
```

#### source type and `next` behaviour

hinhnen treats local and remote sources differently, and that changes what `hinhnen next` does:

- **local only** - `hinhnen next` moves through history. when it reaches the end, it wraps around to the start, so you loop through everything that's been shown.
- **remote only** (bing, unsplash, nasa apod, wallhaven) - `hinhnen next` always fetches a new image from a source.
- **mixed** - local and remote sources in the same config aren't supported.

#### multiple remote sources

if you list several remote sources, hinhnen picks between them using `rotation` and `weight`:

```toml
[sources]
rotation = "weighted_random"

[[sources.list]]
type = "bing"
weight = 1

[[sources.list]]
type = "unsplash"
api_key = "your_api_key_here"
query = "nature"
weight = 2

[[sources.list]]
type = "nasa_apod"
api_key = "your_api_key_here"
weight = 1
```

#### multiple local sources

you can also point hinhnen at several folders, which is handy if you keep wallpapers sorted by category:

```toml
[sources]
rotation = "round_robin"

[[sources.list]]
type = "local"
path = "~/Pictures/Wallpapers/landscapes"
order = "random"
weight = 1

[[sources.list]]
type = "local"
path = "~/Pictures/Wallpapers/minimal"
order = "sequential"
weight = 1
```

---

### cache

downloaded images are stored on disk. the defaults work well for me, but you can change them here:

```toml
[cache]
max_size_mb = 500              # max disk space for cached images
history_size = 100             # how many past wallpapers to remember
dir = "~/.cache/hinhnen/images"  # where to store them
```

hinhnen will remove cache images when the cache grows past `max_size_mb`. 
if you'd like to start fresh, you can run:

```bash
hinhnen clean
```

it deletes files inside the cache folder.

## scripting

if you'd like another program to control hinhnen - a keybind, a status bar, a small script

**option 1: run the cli.** `hinhnen next`, `hinhnen status`

```bash
# a hyprland keybind, for example
bind = $mod, W, exec, hinhnen next
```

**option 2: talk to the socket.** it lives at `$XDG_RUNTIME_DIR/hinhnen.sock`.

a request is a command name:

```json
{"cmd": "next"}
```

the valid commands are the same as the cli's: `next`, `prev`, `pause`, `resume`, `status`, `reload`, `history`, `clean`.

the reply is a json line with a `result` field. there are three shapes:

```json
{"result": "ok", "message": "advanced", "status": { ... }}
{"result": "history", "entries": [ ... ], "cursor": 3}
{"result": "error", "message": "all sources failed"}
```

most commands reply with `ok`.`history` replies with its own shape. anything goes wrong, you'll get `error` message.

here's a one-liner to try it, without using the hinhnen binary:

```bash
echo '{"cmd":"status"}' | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hinhnen.sock
```

or in python:

```python
import json, os, socket

def hinhnen(cmd):
    path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hinhnen.sock")
    with socket.socket(socket.AF_UNIX) as s:
        s.connect(path)
        s.sendall((json.dumps({"cmd": cmd}) + "\n").encode())
        return json.loads(s.makefile().readline())

print(hinhnen("status"))
```

## autostart

add this to your `hyprland.conf`:

```
exec-once = hinhnen daemon
```

if you installed with the script (*install.sh*), autostart is already set up.

---

hinhnen is built for [Hyprland](https://hyprland.org/) and inspired by Windows Spotlight and macOS dynamic wallpapers. thank you for taking a look - i hope it's useful.
