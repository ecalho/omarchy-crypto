# Omarchy Crypto

Bitcoin and favorite crypto prices in the [Omarchy](https://omarchy.org) bar.

The bar shows one coin at a time — with its logo — and rotates through your
favorites on a timer. A popup shows all of them at once with 24 hour change, a
7-day sparkline, and market stats. Clicking a coin in the popup pins it to the
bar, and the choice is written to `shell.json`, so it survives a restart.

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
| [Dashboard Icons](https://github.com/homarr-labs/dashboard-icons) via jsDelivr | Logos for coins that do not ship with the plugin | No |
| JetBrainsMono Nerd Font | Text fallback glyph when no logo loads | No, ships with Omarchy |

No package is installed, no service is started, and nothing outside
`~/.config/omarchy` is written.

## Install

```bash
omarchy plugin add https://github.com/ThalesAugusto0/omarchy-bitcoin.git --enable --yes
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
| Popup  | `↑` `↓`      | move the cursor                         |
| Popup  | `enter`      | pin the selected coin to the bar        |
| Popup  | `r`          | refresh                                 |
| Popup  | `o`          | open the selected coin on coingecko.com |
| Popup  | `esc`        | close                                   |

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
| `showChange`         | `true`                      | Append the 24h percentage to the bar label |
| `compactPrice`       | `false`                     | `$78.9k` instead of `$78,851` |
| `colorizeChange`     | `true`                      | Tint the bar label: theme accent when up, urgent when down |

Coin ids are the ones in a CoinGecko URL — `coingecko.com/en/coins/**dogecoin**`
is `dogecoin`. An id the API does not know is listed at the bottom of the popup
rather than silently dropped.

## Coin logos

A coin resolves to the first mark that loads:

1. a **bundled SVG** in `icons/<id>.svg` — Bitcoin, Ethereum, and Solana ship
   with the plugin, so those three draw with no network at all
2. **[Dashboard Icons](https://github.com/homarr-labs/dashboard-icons)**, at
   `https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/<id>.svg` —
   this is where Monero, Ethereum, Bitcoin and friends come from upstream
3. the **logo CoinGecko itself returned** for the coin, which exists for every
   coin the API knows
4. a **Nerd Font glyph**, drawn as text, if all of the above fail

So a coin you add gets a real mark without this plugin shipping one, and a
machine with no network still draws the coins it ships. Dropping an SVG at
`icons/<id>.svg` and adding the id to `BUNDLED_ICONS` in `Model.js` makes any
coin offline-capable.

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
```

## Files

| File           | What it is |
|----------------|------------|
| `manifest.json`| Plugin declaration and settings schema |
| `Panel.qml`    | Bar pill and popup — the entry point |
| `Service.qml`  | CoinGecko polling, retries, stale state |
| `CoinIcon.qml` | One coin's mark, walking the candidate list to a text fallback |
| `Model.js`     | Parsing, formatting, and icon resolution — no QML |
| `icons/`       | Bundled coin SVGs (Bitcoin, Ethereum, Solana) |

## License

MIT — see [LICENSE](LICENSE).
