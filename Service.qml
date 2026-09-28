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
