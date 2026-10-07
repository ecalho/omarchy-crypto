# Omarchy Crypto

Bitcoin and favorite crypto prices in the [Omarchy](https://omarchy.org) bar.

The bar shows one coin at a time — with its logo — and rotates through your
favorites on a timer. A popup shows all of them at once with 24 hour change, a
lightweight price chart (1h, 4h, 1 day, 1 week, 1 month, or all history, your
choice), and market stats. Clicking a coin in the popup pins it to the bar, and
the choice is written to `shell.json`, so it survives a restart.

Out of the box it follows Bitcoin. Name any coins you want in the `coins`
setting and they appear, logo and all.

Prices come from the free [CoinGecko](https://www.coingecko.com) API. No account
and no API key.

```
BAR     ₿ BTC $78,851 -1.07%

POPUP   ₿ Bitcoin                      BTC / USD · updated 22:36:25   -1.07%
        $78,851  ▼ 24h
        ╭─╮   ╭──╮
        ╯ ╰───╯  ╰──╮     (7 days)
        24h high                                              $80,708
        24h low                                               $77,940
        Market cap                                             $1.58T
        24h volume                                            $42.10B
        ─────────────────────────────────────────────────────────────
        FAVORITES
        ₿ Bitcoin   BTC                            $78,851     -1.07%
        ◈ Ethereum  ETH                             $2,456     -1.60%
        ≋ Solana    SOL                             $97.05     -4.69%
```

## Requirements

Omarchy 4 (the `omarchy-shell` Quickshell host) and `curl`.

External dependencies, all optional to install and all reached over HTTPS at
runtime:

| Dependency | What it is for | Account needed |
|------------|----------------|----------------|
| [CoinGecko public API](https://www.coingecko.com/en/api) | Prices, 24h change, market stats, 7-day sparkline | No, no API key |
| JetBrainsMono Nerd Font | Text fallback glyph when no logo loads | No, ships with Omarchy |

No package is installed and no service is started. Besides
`~/.config/omarchy`, the only thing written is the logo cache under the
Quickshell cache directory (`~/.cache/quickshell/by-shell/<hash>/thales.crypto/icons`).

## Install

```bash
omarchy plugin add https://github.com/ecalho/omarchy-crypto.git --enable --yes
```

The repo is private, so the machine needs credentials *before* this command.
Easiest: `gh auth login` on it — that installs the git credential helper
`omarchy plugin add` reads (the command runs with `GIT_TERMINAL_PROMPT=0`, so
nothing can ever prompt). An ssh key works too, with the scp form instead:

```bash
omarchy plugin add git@github.com:ecalho/omarchy-crypto.git --enable --yes
```

Or by hand, from a clone of this repo:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/thales.crypto
omarchy-shell shell rescanPlugins
omarchy plugin enable thales.crypto
```

Move it around the bar with `omarchy bar move thales.crypto left|center|right`.

## Remove

```bash
omarchy plugin remove thales.crypto --yes
```

That disables the widget, deletes or unlinks the plugin folder, and rescans.
A hand-made symlink is unlinked rather than deleted, so the clone stays put.

The widget's settings live in its entry in `~/.config/omarchy/shell.json`, under
`bar.layout.<section>`. Removing the plugin unloads the widget but leaves that
entry in place. Drop it from Setup > Plugins, or by hand:

```bash
jq 'del(.bar.layout[][] | select(.id == "thales.crypto"))' \
  ~/.config/omarchy/shell.json > /tmp/shell.json &&
  mv /tmp/shell.json ~/.config/omarchy/shell.json
```

Nothing else is left behind — the plugin writes no files of its own, installs no
packages, and touches nothing outside `~/.config/omarchy`.

## Interactions

| Where  | Input        | Action                                  |
|--------|--------------|-----------------------------------------|
| Bar    | left click   | open the popup                          |
| Bar    | right click  | next favorite coin                      |
| Bar    | hover        | hold the rotation on the coin shown      |
| Bar    | middle click | refresh now                             |
| Bar    | scroll       | previous / next favorite coin           |
| Popup  | click a row  | pin that coin to the bar                |
| Popup  | right click a row | open the coin on coingecko.com     |
| Popup  | click the `x` before a favorite | remove it from favorites  |
| Popup  | click a range pill (`1H 4H 1D 1W 1M ALL`) | switch the chart's time range |
| Popup  | `/`          | focus the coin search field             |
| Popup  | `↑` `↓`      | move the cursor                         |
| Popup  | `enter`      | pin the selected coin to the bar        |
| Popup  | `x`          | remove the selected favorite            |
| Popup  | `r`          | refresh                                 |
| Popup  | `o`          | open the selected coin on coingecko.com |
| Popup  | `esc`        | close                                   |
| Search | type         | search CoinGecko for a coin to add      |
| Search | `↑` `↓`      | move through the results                |
| Search | `enter`      | add the selected result to favorites    |
| Search | click a row  | add that coin and pin it to the bar     |

## Settings

Settings live inline on the widget's entry in `~/.config/omarchy/shell.json`,
and are editable from Setup > Plugins.

| Key                  | Default                     | What it does |
|----------------------|-----------------------------|--------------|
| `coins`              | `bitcoin`                   | CoinGecko coin ids, comma-separated, in display order. Empty falls back to `bitcoin` |
| `currency`           | `usd`                       | `usd`, `brl`, `eur`, `gbp`, `jpy`, `cad`, `aud`, `chf`, `cny`, `inr`, `sats`, `btc`, `eth` |
| `primary`            | first coin                  | Which coin the bar shows. Written for you when you pin one |
| `refreshIntervalSec` | `120`                       | Seconds between refreshes, minimum 30 |
| `rotateSeconds`      | `10`                        | Seconds each coin holds the bar. `0` pins the bar to one coin |
| `showIcon`           | `true`                      | Coin logo before the price |
| `showSymbol`         | `true`                      | `BTC`, `ETH`, … before the price |
| `showPrice`          | `true`                      | The price itself in the pill. Off → symbol + percentage only |
| `showChange`         | `true`                      | Append the selected chart range's percentage to the label |
| `compactPrice`       | `false`                     | `$78.9k` instead of `$78,851` |
| `colorizeChange`     | `true`                      | Tint the bar label: theme accent when up, urgent when down |
| `chartRange`         | `1w`                        | Default chart range: `1h`, `4h`, `1d`, `1w`, `1m`, or `all`; its change % is what the bar pill reports |

Coin ids are the ones in a CoinGecko URL — `coingecko.com/en/coins/**dogecoin**`
is `dogecoin`. An id the API does not know is listed at the bottom of the popup
rather than silently dropped.

## Adding coins

The popup has an "ADD A COIN" search field (press `/` from anywhere in the
popup to focus it). Type part of a name — `sol`, `doge`, `fetcht` — and the
top CoinGecko matches appear. Click one, or arrow down to it and press
`enter`, and the coin joins your favorites, its icon is cached, and it is
pinned to the bar. Everything is written to `shell.json`, so it sticks.

Coins you already follow are filtered out of the results, so every row shown
means "not tracked yet". Clearing the field costs no API call — nothing is
fetched until at least two characters are typed.

## Removing coins

Every favorite row in the popup has a small `x` on its left. Click it and the
coin leaves your favorites list immediately; the change is written to
`shell.json`. Removing the coin currently pinned to the bar falls back to the
first remaining favorite (or back to Bitcoin if it was the last one). From the
keyboard, arrow to a favorite and press `x` to drop it.

## Chart ranges

Above the chart in the popup is a row of range pills — `1H 4H 1D 1W 1M ALL`.
They redraw the chart for the coin currently highlighted, and the pill itself
persists in `shell.json` via the `chartRange` setting.

Ranges are drawn from CoinGecko's `market_chart` endpoint and cached per coin,
so bouncing between ranges never re-fetches:

| Range | Data |
|-------|------|
| `1H` / `4H` | the trailing hour / four hours of 5-minute points |
| `1D` | the last day of 5-minute points |
| `1W` | the 7-day sparkline that already comes with every price fetch — zero extra requests |
| `1M` | 30 days of ~30-minute points |
| `ALL` | full history when the free API allows it, otherwise one year |

The numbered caption next to the price switches with the range (e.g. `▲ 1W
+2.4%`) and only ever reports the gain of the range that is selected — it never
substitutes the 24h change. While a dedicated range is being fetched the
caption shows a neutral `– 1M` and a small `…` appears beside the pills. A
header above the pills always states which coin the chart is showing, which
range, and its gain — `Bitcoin · 1M · +7.07%`.

Everything above — hero price, header, chart and the market stats below — is
**pinned to the selected coin**, not the hovered one. Moving the mouse over the
favorites list or walking the cursor with the keyboard only moves the
highlight; the display switches once you actually select a coin (click it, or
press `enter` on it), which also pins it to the bar.

The chart is sized generously and never goes blank mid-session: while a new
range or coin loads, the previous drawing is dimmed and the coin's free 7-day
sparkline steps in immediately, so there is always something to look at.

Hover the chart for detail: a crosshair tracks the pointer and a badge shows
the exact price, the timestamp, and the gain since the start of the range.
It flips to the other side of the line near the edges so it never clips.

## Bar label

The pill composes four independent toggles (Setup → Plugins → Coin ticker):
`showIcon` (logo), `showSymbol` (e.g. `KAS`), `showPrice` (e.g. `$0.0430`) and
`showChange`. So `KAS $0.0430 +2.4%` is just the default; turn `showPrice` off
for a quiet `KAS +2.4%`, or keep any combination you like.

The percentage is the gain of whatever `chartRange` is selected — pick `1M` in
the range pills and the bar follows with the 30-day change. It falls back to
the 24h change only until that range's chart is fetched (the free 7-day
sparkline covers the default `1W` range with zero extra requests).

## Coin logos

A coin resolves to the first mark that loads:

1. a **bundled SVG** in `icons/<id>.svg` — Bitcoin, Ethereum, and Solana ship
   with the plugin, so those three draw with no network at all
2. the **logo CoinGecko returned** for the coin, which exists for every coin
   the API knows
3. a **Nerd Font glyph**, drawn as text, if neither loads

The CoinGecko logo is never loaded by QML straight from the network. It is
downloaded once with `curl` into the Quickshell cache, and only that local file
is shown. The download:

- accepts only `https://` URLs on `coin-images.coingecko.com` or
  `assets.coingecko.com`
- refuses redirects and any answer other than HTTP 200
- stops at 256 KiB, whether or not the server sends a length
- keeps the file only if its first bytes are PNG, JPEG, GIF, or WebP, so SVG
  or any other format never reaches the image decoder

Rejected logos are logged to the shell log and the coin falls back to the
glyph. Dropping an SVG at `icons/<id>.svg` and adding the id to
`BUNDLED_ICONS` in `Model.js` makes any coin offline-capable.

Example:

```json
{
  "id": "thales.crypto",
  "coins": "bitcoin,ethereum,solana,dogecoin",
  "currency": "brl",
  "primary": "bitcoin",
  "refreshIntervalSec": 120,
  "compactPrice": true
}
```

## Rotation

With more than one favorite, the bar walks through them every `rotateSeconds`
and crossfades between coins. Set `rotateSeconds` to `0` to stop on the pinned
coin instead.

Rotating and pinning are different things:

- **Rotating** moves which coin is on screen. Nothing is written down, so the
  bar comes back to the pinned coin after a restart.
- **Pinning** — clicking a coin in the popup, pressing `enter` on it, or
  right-clicking the pill — writes `primary` to `shell.json`. With rotation on,
  the pinned coin is where the cycle starts.

Rotation holds while the popup is open, since the popup already shows every
coin, and while the pointer is on the pill, so a coin you are reading stays put.

While it rotates, the pill reserves room for the widest label its favorites can
produce, so the widgets beside it do not shift every few seconds.

## Rate limits

CoinGecko's free tier allows roughly 30 calls per minute. One refresh is one
call no matter how many coins are configured, but the bar is instantiated once
per monitor, so a three-monitor setup makes three calls per refresh. The default
of 120s leaves plenty of headroom; the minimum accepted is 30s.

A failed refresh — offline, rate limited, a bad response — keeps the last good
prices on screen, dims the bar pill, and says so in the popup. It retries twice
before falling back to the normal cadence.

## IPC

```bash
omarchy-shell thales.crypto toggle     # open/close the popup
omarchy-shell thales.crypto refresh    # fetch now
omarchy-shell thales.crypto next       # pin the next favorite to the bar
omarchy-shell thales.crypto rotate     # advance the rotation without pinning
omarchy-shell thales.crypto price      # print the current bar label
omarchy-shell thales.crypto search "sol"      # query CoinGecko (results pop the UI)
omarchy-shell thales.crypto add dogecoin      # add a coin to favorites and pin it
omarchy-shell thales.crypto remove dogecoin   # drop a coin from favorites
omarchy-shell thales.crypto chart "1m"        # switch chart range and print its change
```

## Files

| File           | What it is |
|----------------|------------|
| `manifest.json`| Plugin declaration and settings schema |
| `Panel.qml`    | Bar pill and popup — the entry point |
| `Service.qml`  | CoinGecko polling, coin search, and chart fetching — with retries and caching |
| `CoinIcon.qml` | One coin's mark, walking the candidate list to a text fallback |
| `Model.js`     | Parsing, formatting, and icon resolution — no QML |
| `icons/`       | Bundled coin SVGs (Bitcoin, Ethereum, Solana) |

## License

MIT — see [LICENSE](LICENSE).
