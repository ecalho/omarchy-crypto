import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  readonly property string coinsSetting: String(setting("coins", ""))
  property var ids: []
  property bool started: false
  readonly property string currency: Model.currencyCode(setting("currency", "usd"))
  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 120)) || 120)
  readonly property string url: Model.marketsUrl(ids, currency)

  property var coins: []
  property var missing: []
  property bool loading: false
  property string lastError: ""
  property var lastUpdated: null
  property bool stale: false
  property int retries: 0
  property var requestIds: []
  property bool refreshQueued: false

  // Coin search, used by the popup's "add a coin" field.
  property string searchText: ""
  property var searchResults: []
  property bool searching: false
  property string searchError: ""
  property string searchRequestText: ""
  property bool searchQueued: false

  // Per-coin market charts, cached so switching ranges back and forth never
  // re-fetches. charts maps "<coinId>|<rangeKey>" to { key, label, points,
  // pct }. The default 1W range reuses the bundled sparkline and costs no
  // request; the rest come from /market_chart, with "max" falling back to a
  // year when the free API refuses it.
  property var charts: ({})
  property bool chartLoading: false
  property string chartError: ""
  property var chartActiveRequest: null
  property var chartPendingRequest: null

  readonly property bool hasData: coins.length > 0

  // Remote coin images, downloaded one at a time through Model.IMAGE_FETCH_SCRIPT.
  // iconFiles maps the API image URL to the validated local file:// URL.
  readonly property string imageCacheDir: Quickshell.cachePath("thales.crypto/icons")
  property var iconFiles: ({})
  property var imageQueue: []
  property var imageRequested: ({})
  property var imageJob: null

  function iconFor(coin) {
    if (!coin || !coin.image) return ""
    var file = iconFiles[coin.image]
    return file === undefined ? "" : file
  }

  function queueImages(list) {
    var queue = imageQueue.slice()
    for (var i = 0; i < list.length; ++i) {
      var coin = list[i]
      if (!coin.image || Model.hasBundledIcon(coin.id) || imageRequested[coin.image]) continue
      imageRequested[coin.image] = true
      queue.push({ id: coin.id, url: coin.image })
    }
    imageQueue = queue
    pumpImages()
  }

  function pumpImages() {
    if (imageProc.running || imageQueue.length === 0) return
    var job = imageQueue[0]
    imageQueue = imageQueue.slice(1)
    job.file = Model.imageCacheFile(imageCacheDir, job.url)
    imageJob = job
    imageProc.command = ["sh", "-c", Model.IMAGE_FETCH_SCRIPT, "sh",
      job.url, job.file, String(Model.MAX_IMAGE_BYTES)]
    imageProc.running = true
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (url === "") {
      coins = []
      missing = []
      lastError = "No coins configured"
      return
    }
    if (fetchProc.running) {
      refreshQueued = true
      return
    }
    retries = 0
    startFetch()
  }

  function startFetch() {
    loading = true
    requestIds = ids
    fetchProc.command = ["curl", "-fsS", "--proto", "=https", "--tlsv1.2",
      "--max-time", "12", "--max-filesize", String(Model.MAX_RESPONSE_BYTES), url]
    fetchProc.running = true
  }

  function applyResponse(raw) {
    var text = String(raw || "").replace(/^\s+|\s+$/g, "")
    if (text === "") {
      failed("Empty response from CoinGecko")
      return
    }
    if (text.length > Model.MAX_RESPONSE_BYTES) {
      failed("CoinGecko response was too large")
      return
    }
    try {
      var parsed = Model.parseMarkets(text, ids)
      coins = parsed
      queueImages(parsed)
      missing = Model.missingIds(ids, parsed)
      lastError = parsed.length === 0 ? "No prices for the configured coins" : ""
      stale = false
      retries = 0
      lastUpdated = new Date()
    } catch (e) {
      failed("Could not read the CoinGecko response")
    }
  }

  function failed(message) {
    lastError = message
    stale = hasData
    if (retries >= 2) return
    retries++
    retryTimer.restart()
  }

  // Query is debounced in the panel; this only runs the request for the
  // text it is given. An empty or too-short query drops any in-flight work
  // instead of fetching, so clearing the field costs no API call.
  function search(query) {
    searchText = Model.searchText(query)
    var nextUrl = Model.searchUrl(searchText)
    if (nextUrl === "") {
      searchQueued = false
      searching = false
      searchError = ""
      searchResults = []
      if (searchProc.running) searchProc.running = false
      return
    }
    if (searchProc.running) {
      searchQueued = true
      return
    }
    startSearch()
  }

  function startSearch() {
    var nextUrl = Model.searchUrl(searchText)
    if (nextUrl === "") return
    searching = true
    searchError = ""
    searchRequestText = searchText
    searchProc.command = ["curl", "-fsS", "--proto", "=https", "--tlsv1.2",
      "--max-time", "10", "--max-filesize", String(Model.MAX_RESPONSE_BYTES), nextUrl]
    searchProc.running = true
  }

  function clearSearch() {
    searchQueued = false
    searchText = ""
    searching = false
    searchError = ""
    searchResults = []
    if (searchProc.running) searchProc.running = false
  }

  // The cached chart for a coin+range, or null while it is unavailable. The
  // sparkline shows whatever this returns and repaints when it changes.
  function chartFor(coin, rangeKey) {
    if (!coin) return null
    var key = Model.chartCacheKey(coin.id, rangeKey)
    var cached = charts[key]
    return cached === undefined ? null : cached
  }

  // Fetch the selected chart once per coin+range and cache it. The 1W range
  // builds instantly from the markets sparkline; other ranges fetch on demand.
  function ensureChart(coin, rangeKey) {
    if (!coin || !coin.id) return
    var key = Model.chartCacheKey(coin.id, rangeKey)
    if (charts[key]) return
    if (chartActiveRequest && chartActiveRequest.key === key) return

    var range = Model.chartRange(rangeKey)
    if (range.key === "1w") {
      var points = Model.sparklineChart(coin, range)
      if (points.length >= 2) {
        var next = Object.assign({}, root.charts)
        next[key] = chartRecord(range, points)
        root.charts = next
        return
      }
    }
    // One curl at a time: fast range changes queue behind the active request
    // instead of racing its completion (like searchQueued does).
    if (chartProc.running) {
      if (!chartPendingRequest)
        chartPendingRequest = { coin: coin, range: range, days: String(range.days) }
      return
    }
    root.startChartFetch(coin, range, String(range.days))
  }

  function startChartFetch(coin, range, days) {
    var url = Model.marketChartUrl(coin.id, root.currency, range)
    if (url === "") {
      chartError = "No chart available for this coin"
      return
    }
    chartActiveRequest = {
      key: Model.chartCacheKey(coin.id, range.key),
      coinId: coin.id,
      rangeKey: range.key,
      days: String(days)
    }
    chartLoading = true
    chartError = ""
    chartProc.command = ["curl", "-fsS", "--proto", "=https", "--tlsv1.2",
      "--max-time", "20", "--max-filesize", String(Model.MAX_RESPONSE_BYTES), url]
    chartProc.running = true
  }

  function chartRecord(range, points) {
    return { key: range.key, label: range.label, points: points, pct: Model.chartChange(points) }
  }

  function clearCharts() {
    charts = {}
    chartError = ""
  }

  onCoinsSettingChanged: syncIds()
  onCurrencyChanged: reset()
  Component.onCompleted: syncIds()

  function syncIds() {
    var next = Model.coinIds(coinsSetting)
    if (started && next.join(",") === ids.join(",")) return
    started = true
    ids = next
    reset()
  }

  function reset() {
    coins = []
    missing = []
    lastUpdated = null
    stale = false
    root.clearCharts()
    refresh()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector { id: outCollector; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }

    onExited: function(exitCode, exitStatus) {
      root.loading = false

      var answeredOldQuestion = root.requestIds.join(",") !== root.ids.join(",")
      if (!answeredOldQuestion) {
        if (exitCode === 0) root.applyResponse(outCollector.text)
        else if (exitCode === 22) root.failed("CoinGecko refused the request (rate limited?)")
        else if (exitCode === 63) root.failed("CoinGecko response was too large")
        else root.failed("Could not reach CoinGecko")
      }

      if (root.refreshQueued || answeredOldQuestion) {
        root.refreshQueued = false
        root.retries = 0
        root.startFetch()
      }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector { id: searchOutCollector; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }

    onExited: function(exitCode, exitStatus) {
      // A cleared field kills the process; that answer is always stale.
      var staleAnswer = root.searchRequestText !== root.searchText
      if (!staleAnswer) {
        root.searching = false
        if (exitCode === 0) {
          try {
            root.searchResults = Model.parseSearch(searchOutCollector.text)
            root.queueImages(root.searchResults)
          } catch (e) {
            root.searchResults = []
            root.searchError = "Could not read the CoinGecko response"
          }
        } else if (exitCode === 22) {
          root.searchResults = []
          root.searchError = "CoinGecko refused the request (rate limited?)"
        } else {
          root.searchResults = []
          root.searchError = "Could not reach CoinGecko"
        }
      }

      if (root.searchQueued) {
        root.searchQueued = false
        root.startSearch()
      }
    }
  }

  Process {
    id: imageProc
    stderr: StdioCollector { id: imageErr; waitForEnd: true }

    onExited: function(exitCode, exitStatus) {
      var job = root.imageJob
      root.imageJob = null
      if (job) {
        if (exitCode === 0) {
          var next = Object.assign({}, root.iconFiles)
          next[job.url] = "file://" + encodeURI(job.file)
          root.iconFiles = next
        } else {
          console.warn("thales.crypto: icon for " + job.id + " rejected (exit " + exitCode + ")",
            String(imageErr.text || "").slice(0, 200))
        }
      }
      root.pumpImages()
    }
  }

  Process {
    id: chartProc
    stdout: StdioCollector { id: chartCollector; waitForEnd: true }

    onExited: function(exitCode, exitStatus) {
      var request = root.chartActiveRequest
      root.chartActiveRequest = null
      root.chartLoading = false
      if (request) {
        var range = Model.chartRange(request.rangeKey)

        if (exitCode === 0) {
          try {
            var points = Model.parseChart(chartCollector.text, range)
            if (points.length >= 2) {
              var next = Object.assign({}, root.charts)
              next[request.key] = root.chartRecord(range, points)
              root.charts = next
              root.chartError = ""
            } else {
              root.chartError = "No chart data for this range"
            }
          } catch (e) {
            root.chartError = "Could not read the chart response"
          }
        } else if (request.days === "max") {
          // CoinGecko's free tier answers days=max with a 401; retry once with
          // a full year. Delivery is unchanged, so the visible label stays ALL.
          var coin = Model.findCoin(root.coins, request.coinId)
          if (coin) {
            var fallback = Object.assign({}, Model.chartRange(request.rangeKey), {
              days: Model.chartRange(request.rangeKey).fallbackDays || 365
            })
            root.startChartFetch(coin, fallback, String(fallback.days))
            return
          }
        } else if (exitCode === 22) {
          root.chartError = "CoinGecko refused the chart request (rate limited?)"
        } else if (exitCode === 63) {
          root.chartError = "Chart response was too large"
        } else {
          root.chartError = "Could not reach the chart API"
        }
      }

      // Serve the next queued range, skipping any that got cached meanwhile.
      var pending = root.chartPendingRequest
      root.chartPendingRequest = null
      if (pending && !root.charts[Model.chartCacheKey(pending.coin.id, pending.range.key)])
        root.startChartFetch(pending.coin, pending.range, pending.days)
    }
  }

  Timer {
    id: retryTimer
    interval: 4000
    onTriggered: if (!fetchProc.running) root.startFetch()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }
}
