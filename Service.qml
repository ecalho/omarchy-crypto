import QtQuick
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
    fetchProc.command = ["curl", "-fsS", "--max-time", "12",
      "--max-filesize", String(Model.MAX_RESPONSE_BYTES), url]
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
