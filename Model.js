var API_BASE = "https://api.coingecko.com/api/v3/coins/markets"
var SEARCH_API = "https://api.coingecko.com/api/v3/search"
var MARKET_CHART_API = "https://api.coingecko.com/api/v3/coins/"
var COIN_PAGE = "https://www.coingecko.com/en/coins/"
var DEFAULT_COIN = "bitcoin"

// Chart ranges shown in the popup. hours > 0 slices the trailing window out
// of a days=1 response (5-minute points); days=max falls back to one year
// when the free API rejects it (it currently answers "max" with a 401).
var CHART_RANGES = [
  { key: "1h", label: "1H", days: 1, hours: 1, max: 64 },
  { key: "4h", label: "4H", days: 1, hours: 4, max: 96 },
  { key: "1d", label: "1D", days: 1, hours: 0, max: 128 },
  { key: "1w", label: "1W", days: 7, hours: 0, max: 96 },
  { key: "1m", label: "1M", days: 30, hours: 0, max: 128 },
  { key: "all", label: "ALL", days: "max", hours: 0, max: 160, fallbackDays: 365 }
]

// Bounds on API-controlled data, so a compromised endpoint cannot grow memory
// without limit: the byte cap is enforced by curl --max-filesize and re-checked
// before JSON.parse, the item caps while normalizing the parsed payload.
var MAX_RESPONSE_BYTES = 2 * 1024 * 1024
var MAX_COINS = 250
var MAX_SEARCH_RESULTS = 8
var MIN_SEARCH_LENGTH = 2
var MAX_SPARKLINE_POINTS = 512
var MAX_CHART_RAW_POINTS = 6000
var MAX_CHART_POINTS = 160
var MAX_IMAGE_URL_LENGTH = 2048
var MAX_TEXT_LENGTH = 64

// Only download remote coin images over HTTPS from CoinGecko's own image hosts;
// anything else in the API payload is dropped and the glyph fallback shows.
var IMAGE_HOSTS = {
  "coin-images.coingecko.com": true,
  "assets.coingecko.com": true
}

function clampText(value, fallback) {
  var text = String(value === undefined || value === null || value === "" ? fallback : value)
  return text.slice(0, MAX_TEXT_LENGTH)
}

function safeImageUrl(raw) {
  var url = String(raw || "")
  if (url === "" || url.length > MAX_IMAGE_URL_LENGTH) return ""
  var match = url.match(/^https:\/\/([a-z0-9.-]+)(?::443)?[\/?#]/i)
  if (!match || IMAGE_HOSTS[match[1].toLowerCase()] !== true) return ""
  return url
}

var BUNDLED_ICONS = {
  "bitcoin": true,
  "ethereum": true,
  "solana": true
}

// Remote coin images never reach QML as network URLs. Service.qml downloads
// them with IMAGE_FETCH_SCRIPT into the shell cache, and only the resulting
// local file is handed to Image. The script refuses redirects and non-200
// answers, caps the body at MAX_IMAGE_BYTES, and keeps the file only when its
// magic bytes are PNG, JPEG, GIF, or WebP, so SVG or other formats never load.
var MAX_IMAGE_BYTES = 256 * 1024
var IMAGE_FETCH_SCRIPT = [
  'set -eu',
  'url=$1 dest=$2 max=$3',
  '[ -s "$dest" ] && exit 0',
  'mkdir -p "${dest%/*}"',
  'tmp=$(mktemp "$dest.XXXXXX")',
  'trap \'rm -f "$tmp"\' EXIT',
  'code=$(curl -fsS --proto =https --proto-redir =https --tlsv1.2 --max-redirs 0 --max-time 10 --max-filesize "$max" -o "$tmp" -w "%{http_code}" "$url")',
  '[ "$code" = 200 ] || exit 64',
  'size=$(wc -c < "$tmp")',
  '[ "$size" -gt 0 ] && [ "$size" -le "$max" ] || exit 63',
  'magic=$(head -c 12 "$tmp" | od -An -tx1 | tr -d " \\n")',
  'case "$magic" in 89504e470d0a1a0a*|ffd8ff*|47494638*|52494646????????57454250) ;; *) exit 65 ;; esac',
  'mv -f "$tmp" "$dest"',
  'trap - EXIT'
].join("\n")

function hasBundledIcon(id) {
  return BUNDLED_ICONS[id] === true
}

function imageCacheFile(dir, url) {
  return String(dir) + "/" + Qt.md5(String(url)) + ".img"
}

function isLocalUrl(url) {
  return /^(file|qrc):/i.test(String(url))
}

function iconCandidates(coin, bundledBase, cachedFile) {
  if (!coin) return []
  var list = []
  if (hasBundledIcon(coin.id)) list.push(String(bundledBase) + coin.id + ".svg")
  if (cachedFile) list.push(String(cachedFile))
  return list.filter(isLocalUrl)
}

var GLYPHS = {
  "bitcoin": ""
}
var FALLBACK_GLYPH = ""

var CURRENCY_SYMBOLS = {
  "usd": "$", "brl": "R$", "eur": "€", "gbp": "£", "jpy": "¥",
  "cad": "C$", "aud": "A$", "chf": "CHF ", "cny": "¥", "inr": "₹",
  "btc": "₿", "eth": "Ξ", "sats": ""
}

function coinIds(raw) {
  var parts = String(raw || "").split(/[,\s]+/)
  var seen = {}
  var ids = []
  for (var i = 0; i < parts.length; ++i) {
    var id = parts[i].replace(/^\s+|\s+$/g, "").toLowerCase()
    if (id === "" || seen[id]) continue
    seen[id] = true
    ids.push(id)
  }
  return ids.length > 0 ? ids : [DEFAULT_COIN]
}

function currencyCode(raw) {
  var code = String(raw || "usd").replace(/^\s+|\s+$/g, "").toLowerCase()
  return code === "" ? "usd" : code
}

function marketsUrl(ids, currency) {
  if (!ids || ids.length === 0) return ""
  return API_BASE
    + "?vs_currency=" + encodeURIComponent(currencyCode(currency))
    + "&ids=" + encodeURIComponent(ids.join(","))
    + "&order=market_cap_desc&per_page=250&page=1"
    + "&sparkline=true&price_change_percentage=24h&locale=en"
}

function coinPageUrl(id) {
  return COIN_PAGE + encodeURIComponent(String(id || ""))
}

function chartRange(key) {
  var want = String(key || "1w").toLowerCase()
  for (var i = 0; i < CHART_RANGES.length; ++i) {
    if (CHART_RANGES[i].key === want) return CHART_RANGES[i]
  }
  return CHART_RANGES[3]
}

function chartRangeLabel(key) {
  return chartRange(key).label
}

function chartCacheKey(id, rangeKey) {
  return String(id || "") + "|" + chartRange(rangeKey).key
}

function marketChartUrl(id, currency, range) {
  id = String(id || "")
  if (id === "" || !range || range.days === undefined) return ""
  return MARKET_CHART_API + encodeURIComponent(id)
    + "/market_chart?vs_currency=" + encodeURIComponent(currencyCode(currency))
    + "&days=" + encodeURIComponent(String(range.days))
}

// Parse a market_chart payload into [{t,p}, ...] points: small trailing
// windows (1h/4h) are sliced out, everything is downsampled to the range's
// drawing budget so a course 30-day line stays light.
function parseChart(raw, range) {
  var parsed = JSON.parse(String(raw))
  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.prices))
    throw new Error("unexpected chart response shape")

  var points = []
  var count = Math.min(parsed.prices.length, MAX_CHART_RAW_POINTS)
  for (var i = 0; i < count; ++i) {
    var pair = parsed.prices[i]
    var value = toNumber(pair && pair[1])
    if (!isFinite(value) || pair[0] === undefined) continue
    points.push({ t: pair[0], p: value })
  }
  if (points.length < 2) return []
  if (range && range.hours > 0) points = tailWindow(points, range.hours * 3600000)
  return downsampleChart(points, range && range.max ? range.max : MAX_CHART_POINTS)
}

function tailWindow(points, ms) {
  var end = points[points.length - 1].t
  var start = end - ms
  var tail = []
  for (var i = points.length - 1; i >= 0; --i) {
    if (points[i].t < start) break
    tail.push(points[i])
  }
  tail.reverse()
  return tail.length >= 2 ? tail : points.slice()
}

function downsampleChart(points, maxPoints) {
  if (points.length <= maxPoints) return points
  var count = Math.max(2, Math.round(Number(maxPoints)) || MAX_CHART_POINTS)
  var step = (points.length - 1) / (count - 1)
  var out = []
  for (var i = 0; i < count; ++i) {
    var index = Math.min(points.length - 1, Math.round(i * step))
    out.push(points[index])
  }
  return out
}

function chartChange(points) {
  if (!points || points.length < 2) return NaN
  return sparklineChange([toNumber(points[0].p), toNumber(points[points.length - 1].p)])
}

// The 7-day range reuses the sparkline already returned by the markets API,
// so the default chart never costs an extra request.
function sparklineChart(coin, range) {
  if (!coin || !Array.isArray(coin.sparkline) || coin.sparkline.length < 2) return []
  var now = Date.now()
  var start = now - 7 * 86400000
  var points = []
  for (var i = 0; i < coin.sparkline.length && i < MAX_SPARKLINE_POINTS; ++i) {
    var value = toNumber(coin.sparkline[i])
    if (!isFinite(value)) continue
    points.push({
      t: start + Math.round((now - start) * i / (coin.sparkline.length - 1)),
      p: value
    })
  }
  return downsampleChart(points, range && range.max ? range.max : MAX_CHART_POINTS)
}

function chartSeries(points, buckets) {
  if (!points || points.length < 2) return null
  var count = Math.max(2, Math.min(buckets || 96, points.length))
  var step = (points.length - 1) / (count - 1)
  var values = []
  var indices = []
  var min = Infinity
  var max = -Infinity
  for (var i = 0; i < count; ++i) {
    var index = Math.round(i * step)
    var value = points[index].p
    if (!isFinite(value)) continue
    indices.push(index)
    values.push(value)
    if (value < min) min = value
    if (value > max) max = value
  }
  if (values.length < 2) return null
  var span = max - min
  var normalized = []
  for (var j = 0; j < values.length; ++j) {
    normalized.push(span === 0 ? 0.5 : (values[j] - min) / span)
  }
  return { values: normalized, min: min, max: max, indices: indices }
}

function searchText(raw) {
  return String(raw === undefined || raw === null ? "" : raw).replace(/^\s+|\s+$/g, "")
}

// Empty means "do not search": too short a query floods the free API and
// returns nothing useful anyway.
function searchUrl(query) {
  var text = searchText(query)
  if (text.length < MIN_SEARCH_LENGTH) return ""
  return SEARCH_API + "?query=" + encodeURIComponent(text)
}

function parseSearch(raw) {
  var parsed = JSON.parse(String(raw))
  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.coins))
    throw new Error("unexpected search response shape")

  var results = []
  var seen = {}
  var count = Math.min(parsed.coins.length, MAX_COINS)
  for (var i = 0; i < count; ++i) {
    var entry = parsed.coins[i]
    if (!entry || typeof entry !== "object" || !entry.id) continue
    var id = clampText(entry.id, "").toLowerCase()
    if (id === "" || seen[id]) continue
    seen[id] = true
    results.push({
      id: id,
      name: clampText(entry.name, id),
      symbol: clampText(entry.symbol, "").toUpperCase(),
      rank: toNumber(entry.market_cap_rank),
      image: safeImageUrl(entry.thumb)
    })
    if (results.length >= MAX_SEARCH_RESULTS) break
  }
  return results
}

function toNumber(value) {
  var n = Number(value)
  return isFinite(n) ? n : NaN
}

function parseMarkets(raw, ids) {
  var parsed = JSON.parse(String(raw))
  if (!Array.isArray(parsed)) throw new Error("unexpected response shape")

  var byId = {}
  var count = Math.min(parsed.length, MAX_COINS)
  for (var i = 0; i < count; ++i) {
    var entry = parsed[i]
    if (!entry || typeof entry !== "object" || !entry.id) continue
    byId[clampText(entry.id, "").toLowerCase()] = normalizeCoin(entry)
  }

  var coins = []
  for (var j = 0; j < ids.length; ++j) {
    var coin = byId[ids[j]]
    if (coin) coins.push(coin)
  }
  return coins
}

function normalizeCoin(entry) {
  var spark = entry.sparkline_in_7d && Array.isArray(entry.sparkline_in_7d.price)
    ? entry.sparkline_in_7d.price.slice(0, MAX_SPARKLINE_POINTS)
    : []
  return {
    id: clampText(entry.id, "").toLowerCase(),
    name: clampText(entry.name, entry.id),
    symbol: clampText(entry.symbol, "").toUpperCase(),
    price: toNumber(entry.current_price),
    change24h: toNumber(entry.price_change_percentage_24h),
    high24h: toNumber(entry.high_24h),
    low24h: toNumber(entry.low_24h),
    marketCap: toNumber(entry.market_cap),
    volume: toNumber(entry.total_volume),
    rank: toNumber(entry.market_cap_rank),
    image: safeImageUrl(entry.image),
    sparkline: spark
  }
}

function missingIds(ids, coins) {
  var known = {}
  for (var i = 0; i < coins.length; ++i) known[coins[i].id] = true
  var missing = []
  for (var j = 0; j < ids.length; ++j) if (!known[ids[j]]) missing.push(ids[j])
  return missing
}

function findCoin(coins, id) {
  if (!coins) return null
  for (var i = 0; i < coins.length; ++i) if (coins[i].id === id) return coins[i]
  return null
}

function rotatedCoin(coins, primaryId, offset) {
  if (!coins || coins.length === 0) return null
  var base = coinIndex(coins, primaryId)
  if (base < 0) base = 0
  var step = Math.round(Number(offset))
  if (!isFinite(step)) step = 0
  var index = (base + step) % coins.length
  if (index < 0) index += coins.length
  return coins[index]
}

function coinIndex(coins, id) {
  if (!coins) return -1
  for (var i = 0; i < coins.length; ++i) if (coins[i].id === id) return i
  return -1
}

function resolvePrimaryId(ids, wanted) {
  var want = String(wanted || "").toLowerCase()
  if (want !== "" && ids.indexOf(want) !== -1) return want
  return ids.length > 0 ? ids[0] : ""
}

function stepPrimaryId(ids, current, step) {
  if (!ids || ids.length === 0) return ""
  var index = ids.indexOf(String(current || "").toLowerCase())
  if (index === -1) index = 0
  var next = (index + step) % ids.length
  if (next < 0) next += ids.length
  return ids[next]
}

function groupDigits(text) {
  var parts = String(text).split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return parts.join(".")
}

function currencySymbol(currency) {
  var code = currencyCode(currency)
  var symbol = CURRENCY_SYMBOLS[code]
  return symbol === undefined ? code.toUpperCase() + " " : symbol
}

function currencySuffix(currency) {
  return currencyCode(currency) === "sats" ? " sats" : ""
}

function priceDecimals(value) {
  var abs = Math.abs(value)
  if (!isFinite(abs)) return 2
  if (abs >= 1000) return 0
  if (abs >= 1) return 2
  if (abs >= 0.01) return 4
  if (abs >= 0.0001) return 6
  return 8
}

function formatPrice(value, currency, compact) {
  if (!isFinite(value)) return "—"
  var body = compact && Math.abs(value) >= 1000
    ? compactNumber(value)
    : groupDigits(value.toFixed(priceDecimals(value)))
  return currencySymbol(currency) + body + currencySuffix(currency)
}

function compactNumber(value) {
  if (!isFinite(value)) return "—"
  var abs = Math.abs(value)
  var sign = value < 0 ? "-" : ""
  if (abs >= 1e12) return sign + trimZeros((abs / 1e12).toFixed(2)) + "T"
  if (abs >= 1e9) return sign + trimZeros((abs / 1e9).toFixed(2)) + "B"
  if (abs >= 1e6) return sign + trimZeros((abs / 1e6).toFixed(2)) + "M"
  if (abs >= 1e3) return sign + trimZeros((abs / 1e3).toFixed(1)) + "k"
  return sign + trimZeros(abs.toFixed(2))
}

function trimZeros(text) {
  return String(text).replace(/\.?0+$/, "")
}

function formatLargeCurrency(value, currency) {
  if (!isFinite(value)) return "—"
  return currencySymbol(currency) + compactNumber(value) + currencySuffix(currency)
}

function formatChange(pct) {
  if (!isFinite(pct)) return ""
  var sign = pct > 0 ? "+" : (pct < 0 ? "" : "")
  return sign + pct.toFixed(2) + "%"
}

function changeDirection(pct) {
  if (!isFinite(pct) || pct === 0) return 0
  return pct > 0 ? 1 : -1
}

function changeGlyph(pct) {
  var direction = changeDirection(pct)
  if (direction > 0) return "▲"
  if (direction < 0) return "▼"
  return "–"
}

function glyphFor(coin) {
  if (!coin) return FALLBACK_GLYPH
  var glyph = GLYPHS[coin.id]
  return glyph === undefined ? FALLBACK_GLYPH : glyph
}

function barLabel(coin, options) {
  if (!coin) return ""
  var pct = isFinite(options.changePct) ? options.changePct : coin.change24h
  var parts = []
  if (options.showSymbol !== false && coin.symbol !== "") parts.push(coin.symbol)
  if (options.showPrice !== false)
    parts.push(formatPrice(coin.price, options.currency, options.compactPrice))
  if (options.showChange !== false) {
    var change = formatChange(pct)
    if (change !== "") parts.push(change)
  }
  return parts.join(" ")
}

function widestBarLabel(coins, options) {
  var widest = ""
  if (!coins) return widest
  for (var i = 0; i < coins.length; ++i) {
    var label = barLabel(coins[i], options)
    if (label.length > widest.length) widest = label
  }
  return widest
}

function verticalBarLines(coin, options) {
  if (!coin) return []
  var pct = isFinite(options.changePct) ? options.changePct : coin.change24h
  var lines = []
  if (options.showSymbol !== false && coin.symbol !== "") lines.push(coin.symbol)
  if (options.showPrice !== false)
    lines.push(isFinite(coin.price) ? compactNumber(coin.price) : "—")
  if (options.showChange !== false) {
    var change = formatChange(pct)
    if (change !== "") lines.push(change)
  }
  return lines
}

function sparklinePoints(values, buckets) {
  if (!values || values.length < 2) return null
  var count = Math.max(2, Math.min(buckets || 96, values.length))
  var step = (values.length - 1) / (count - 1)
  var sampled = []
  var min = Infinity
  var max = -Infinity
  for (var i = 0; i < count; ++i) {
    var value = toNumber(values[Math.round(i * step)])
    if (!isFinite(value)) continue
    sampled.push(value)
    if (value < min) min = value
    if (value > max) max = value
  }
  if (sampled.length < 2) return null

  var span = max - min
  var normalized = []
  for (var j = 0; j < sampled.length; ++j) {
    normalized.push(span === 0 ? 0.5 : (sampled[j] - min) / span)
  }
  return { values: normalized, min: min, max: max }
}

function sparklineChange(values) {
  if (!values || values.length < 2) return NaN
  var first = toNumber(values[0])
  var last = toNumber(values[values.length - 1])
  if (!isFinite(first) || !isFinite(last) || first === 0) return NaN
  return ((last - first) / first) * 100
}

function updatedText(date) {
  if (!date) return "never updated"
  return "updated " + Qt.formatDateTime(date, "HH:mm:ss")
}

function heroMeta(coin, currency, date, stale) {
  var bits = []
  if (coin && coin.symbol !== "") bits.push(coin.symbol + " / " + currencyCode(currency).toUpperCase())
  bits.push(stale ? "stale · " + updatedText(date) : updatedText(date))
  return bits.join(" · ")
}
