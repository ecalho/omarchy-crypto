import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ecalho.crypto"
  ipcTarget: "ecalho.crypto"
  manageIpc: false

  property int coinIndex: 0
  property bool cursorActive: false

  readonly property string chartRangeKey: String(setting("chartRange", "1w") || "1w")
  readonly property string chartRangeLabel: Model.chartRangeLabel(root.chartRangeKey)
  readonly property real activeChartPct: {
    // Only ever report the percentage for the exact range that is selected,
    // so the caption can't quietly show the 24h change under a "1M" label
    // while the dedicated fetch runs. It is NaN (no number) until ready.
    if (!root.displayCoin) return NaN
    var chart = service.chartFor(root.displayCoin, root.chartRangeKey)
    return chart && isFinite(chart.pct) ? chart.pct : NaN
  }
  readonly property bool chartBusy: service.chartActiveRequest !== null
    && root.displayCoin !== null
    && service.chartActiveRequest.key === Model.chartCacheKey(root.displayCoin.id, root.chartRangeKey)

  // The chart header ("Bitcoin · 1M · +7.07%") follows the selected (pinned)
  // coin and whichever range is active, so the popup always states what the
  // chart beneath it is showing. Hovering the favorites list only moves the
  // highlight; the display changes once a coin is actually selected.
  readonly property string chartHeaderText: {
    var name = root.displayCoin ? root.displayCoin.name : "Crypto"
    var bits = [name]
    if (root.chartRangeLabel !== "") bits.push(root.chartRangeLabel)
    if (isFinite(root.activeChartPct)) bits.push(Model.formatChange(root.activeChartPct))
    else if (root.chartBusy) bits.push("…")
    return bits.join(" · ")
  }

  readonly property bool vertical: bar ? bar.vertical : false

  readonly property var coins: service.coins
  readonly property string displayId: Model.resolvePrimaryId(service.ids, setting("primary", ""))
  readonly property var displayCoin: Model.findCoin(coins, displayId)
  readonly property var selectedCoin: coins.length > 0
    ? coins[Math.max(0, Math.min(coinIndex, coins.length - 1))]
    : null

  property int searchIndex: 0

  // Search hits that are not favorites yet, so every row means "add this one".
  readonly property var searchResults: {
    var out = []
    for (var i = 0; i < service.searchResults.length; ++i) {
      var result = service.searchResults[i]
      if (service.ids.indexOf(result.id) === -1) out.push(result)
    }
    return out
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool showIcon: setting("showIcon", true) === true
  readonly property bool showSymbol: setting("showSymbol", true) === true
  // Bar layout picks how much the pill shows: "full" keeps the price,
  // "compact" drops it so the pill reads as logo + ticker + percentage only.
  // A legacy `showPrice` toggle is still honoured when `barStyle` is unset.
  readonly property string barStyle: {
    var style = setting("barStyle", "")
    if (style === "full" || style === "compact") return style
    return setting("showPrice", true) === false ? "compact" : "full"
  }
  readonly property bool showPrice: root.barStyle !== "compact"
  readonly property bool showChange: setting("showChange", true) === true
  readonly property bool compactPrice: setting("compactPrice", false) === true
  readonly property bool colorizeChange: setting("colorizeChange", true) === true
  readonly property int rotateSeconds: {
    var seconds = Math.floor(Number(setting("rotateSeconds", 10)))
    if (!isFinite(seconds) || seconds <= 0) return 0
    return Math.max(2, Math.min(3600, seconds))
  }

  // The percentage the bar pill reports follows the selected chart range
  // (e.g. the 1M gain) instead of the 24h change. Falls back to the 24h
  // change only while that range's chart has not been fetched yet, and the
  // free 7-day sparkline covers the default 1W range with no extra request.
  readonly property real barChangePct: {
    if (!root.displayCoin) return NaN
    var record = service.chartFor(root.displayCoin, root.chartRangeKey)
    if (record && isFinite(record.pct)) return record.pct
    if (root.chartRangeKey === "1w" && Array.isArray(root.displayCoin.sparkline))
      return Model.sparklineChange(root.displayCoin.sparkline)
    return isFinite(root.displayCoin.change24h) ? root.displayCoin.change24h : NaN
  }

  readonly property var labelOptions: ({
    currency: service.currency,
    showSymbol: root.showSymbol,
    showPrice: root.showPrice,
    showChange: root.showChange,
    compactPrice: root.compactPrice,
    changePct: root.barChangePct
  })

  property real pillOpacity: 1.0

  readonly property string barText: Model.barLabel(displayCoin, labelOptions)
  readonly property var barLines: Model.verticalBarLines(displayCoin, labelOptions)
  readonly property int displayDirection: displayCoin ? Model.changeDirection(root.barChangePct) : 0

  readonly property real pillIconSize: Math.round(Style.bar.iconFont * 1.15)

  readonly property string widestBarText: rotateSeconds > 0
    ? Model.widestBarLabel(coins, labelOptions)
    : ""
  readonly property real reservedPillWidth: pillMetrics.width
    + (pillMetrics.width > 0 && showIcon ? pillIconSize + Style.space(6) : 0)

  function changeColor(pct, fallback) {
    var direction = Model.changeDirection(pct)
    if (direction > 0) return Color.accent
    if (direction < 0) return root.urgent
    return fallback
  }

  function refresh() {
    service.refresh()
  }

  function showCoin(id, persist) {
    if (!id || id === root.displayId) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.primary = id

    if (!persist) {
      root.settings = entry
      return
    }
    root.setPrimary(id)
  }

  function rotate() {
    if (root.rotateSeconds <= 0 || root.coins.length < 2) return
    var next = Model.rotatedCoin(root.coins, root.displayId, 1)
    root.showCoin(next ? next.id : "", false)
  }

  function setPrimary(id) {
    if (!id || id === root.displayId) return
    root.persistSettings({ primary: id })
  }

  // Merge a patch into the widget settings and write them back to this
  // widget's shell.json entry, so the choice survives a restart.
  function persistSettings(patch) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var field in patch) entry[field] = patch[field]

    var peers = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    for (var i = 0; i < peers.length; ++i) {
      if (peers[i] && peers[i] !== root && "settings" in peers[i]) peers[i].settings = entry
    }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Add a searched coin to the favorites and pin it to the bar.
  function addCoin(id) {
    var wanted = String(id || "").toLowerCase()
    if (wanted === "") return
    var ids = service.ids.slice()
    if (ids.indexOf(wanted) === -1) ids.push(wanted)
    root.persistSettings({ coins: ids.join(","), primary: wanted })
    root.clearSearch()
    Qt.callLater(function() { if (searchField) searchField.forceActiveFocus() })
  }

  // Drop a coin from the favorites. If the pinned coin is the one removed,
  // fall back to the first remaining favorite (or reset to the default).
  function removeCoin(id) {
    var wanted = String(id || "").toLowerCase()
    if (wanted === "") return
    var ids = service.ids.slice()
    var index = ids.indexOf(wanted)
    if (index === -1) return
    ids.splice(index, 1)
    var patch = { coins: ids.join(",") }
    if (root.displayId === wanted) patch.primary = ids.length > 0 ? ids[0] : ""
    root.persistSettings(patch)
  }

  function focusSearch() {
    if (searchField) searchField.forceActiveFocus()
  }

  function clearSearch() {
    searchDebounce.stop()
    if (searchField && searchField.text !== "") searchField.text = ""
    else service.clearSearch()
    searchIndex = 0
  }

  function moveSearchCursor(step) {
    var count = root.searchResults.length
    if (count === 0) return
    searchIndex = Math.max(0, Math.min(count - 1, searchIndex + step))
    scrollItemIntoView(searchColumn && searchIndex < searchColumn.children.length
      ? searchColumn.children[searchIndex] : null)
  }

  function activateSearch() {
    if (root.searchResults.length === 0) return
    var result = root.searchResults[Math.max(0, Math.min(searchIndex, root.searchResults.length - 1))]
    if (result) root.addCoin(result.id)
  }

  function cyclePrimary(step) {
    root.setPrimary(Model.stepPrimaryId(service.ids, root.displayId, step))
  }

  // Persist the chosen chart range; the wheel/favorites logic does not touch it.
  function setChartRange(key) {
    var normalized = Model.chartRange(key).key
    if (normalized !== root.chartRangeKey) root.persistSettings({ chartRange: normalized })
    if (chartDebounce) chartDebounce.restart()
  }

  // Bar layout: "full" keeps the price, "compact" drops it. Written back to
  // shell.json like every other choice made from the popup.
  function setBarStyle(style) {
    var wanted = style === "compact" ? "compact" : "full"
    if (wanted !== root.barStyle) root.persistSettings({ barStyle: wanted })
  }

  function openCoinPage(coin) {
    if (!coin || !root.bar) return
    root.bar.run("xdg-open " + Util.shellQuote(Model.coinPageUrl(coin.id)))
  }

  function ensureCursor() {
    if (coins.length === 0) {
      coinIndex = 0
      return
    }
    if (coinIndex >= coins.length) coinIndex = coins.length - 1
    if (coinIndex < 0) coinIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0 || coins.length === 0) return
    coinIndex = Math.max(0, Math.min(coins.length - 1, coinIndex + dy))
    scrollCursorIntoView()
  }

  function setCoinCursor(index) {
    cursorActive = true
    coinIndex = index
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (selectedCoin) setPrimary(selectedCoin.id)
  }

  function scrollCursorIntoView() {
    if (!coinColumn || coinIndex < 0 || coinIndex >= coinColumn.children.length) return
    scrollItemIntoView(coinColumn.children[coinIndex])
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item || !panelFlick) return
      var margin = Style.space(6)
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewTop + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    root.clearSearch()
    var index = Model.coinIndex(coins, displayId)
    coinIndex = index === -1 ? 0 : index
    if (panelFlick) panelFlick.contentY = 0
    service.refresh()
    if (chartDebounce) chartDebounce.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Coalesces coin/range switches so selection flicker does not hammer the
  // API. It tracks the selected (pinned) coin, not the hovered one.
  Timer {
    id: chartDebounce
    interval: 200
    onTriggered: service.ensureChart(root.displayCoin, root.chartRangeKey)
  }

  onDisplayCoinChanged: if (root.chartDebounce) root.chartDebounce.restart()

  Service {
    id: service
    settings: root.settings
  }

  Connections {
    target: service
    function onCoinsChanged() {
      root.ensureCursor()
      if (root.chartDebounce) root.chartDebounce.restart()
    }
  }

  Timer {
    interval: root.rotateSeconds * 1000
    repeat: true
    running: root.rotateSeconds > 0 && !root.opened && !pillHover.hovered
    onTriggered: pillSwap.restart()
  }

  // Coalesces typing into one search call, and never fires for a query the
  // API would reject outright.
  Timer {
    id: searchDebounce
    interval: 350
    onTriggered: service.search(searchField.text)
  }

  SequentialAnimation {
    id: pillSwap

    PropertyAnimation {
      target: root; property: "pillOpacity"
      to: 0.0; duration: 160; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.rotate()
    }
    PropertyAnimation {
      target: root; property: "pillOpacity"
      to: 1.0; duration: 240; easing.type: Easing.InQuad
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function next(): string { root.cyclePrimary(1); return root.displayId }
    function rotate(): string { root.rotate(); return root.displayId }
    function previous(): string { root.cyclePrimary(-1); return root.displayId }
    function primary(): string { return root.displayId }
    function price(): string { return root.barText }
    function search(q: string): string { service.search(q); return "ok" }
    function add(id: string): string { root.addCoin(id); return "ok" }
    function remove(id: string): string { root.removeCoin(id); return "ok" }
    function chart(range: string): string {
      var key = Model.chartRange(range).key
      if (key !== root.chartRangeKey) root.persistSettings({ chartRange: key })
      service.ensureChart(root.displayCoin, key)
      var label = Model.chartRange(key).label
      var entry = service.chartFor(root.displayCoin, key)
      if (entry) return label + " " + Model.formatChange(entry.pct)
        + " (" + entry.points.length + " pts)"
      if (service.chartError !== "") return label + " error: " + service.chartError
      return label + " loading"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.displayCoin !== null
    fixedWidth: root.vertical
      ? -1
      : Math.round(Math.max(pillRow.implicitWidth, root.reservedPillWidth) + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical
      ? Math.round(((root.showIcon ? 1 : 0) + root.barLines.length) * Style.bar.iconSlot)
      : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    active: root.colorizeChange && root.displayDirection !== 0
    activeColor: root.displayDirection > 0 ? Color.accent : root.urgent
    dimmed: service.stale
    tooltipText: root.opened || !root.displayCoin ? "" : root.displayCoin.name

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cyclePrimary(1)
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.cyclePrimary(delta > 0 ? -1 : 1) }

    HoverHandler {
      id: pillHover
    }

    TextMetrics {
      id: pillMetrics
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      text: root.widestBarText
    }

    readonly property color labelColor: button.active && button.useActiveColor
      ? button.activeColor
      : button.foreground

    Row {
      id: pillRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(6)
      opacity: root.pillOpacity

      CoinIcon {
        visible: root.showIcon
        anchors.verticalCenter: parent.verticalCenter
        coin: root.displayCoin
        cachedFile: service.iconFor(root.displayCoin)
        size: root.pillIconSize
        fallbackColor: button.labelColor
        fontFamily: button.fontFamily
      }

      Text {

        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.barText
        color: button.labelColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }

    Column {
      id: pillColumn
      visible: root.vertical
      anchors.fill: parent
      opacity: root.pillOpacity

      Item {
        visible: root.showIcon
        width: pillColumn.width
        height: Style.bar.iconSlot

        CoinIcon {
          anchors.centerIn: parent
          coin: root.displayCoin
          cachedFile: service.iconFor(root.displayCoin)
          size: root.pillIconSize
          fallbackColor: button.labelColor
          fontFamily: button.fontFamily
        }
      }

      Repeater {
        model: root.barLines

        OpticalGlyph {
          required property string modelData
          width: pillColumn.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.85 : button.fontSize
          color: button.labelColor
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onDeleteRequested: if (root.cursorActive && root.selectedCoin) root.removeCoin(root.selectedCoin.id)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (key === "r") root.refresh()
        else if (key === "o") root.openCoinPage(root.cursorActive ? root.selectedCoin : root.displayCoin)
        else if (key === "/") root.focusSearch()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: root.displayCoin ? root.displayCoin.name : "Crypto"
            meta: root.displayCoin
              ? Model.heroMeta(root.displayCoin, service.currency, service.lastUpdated, service.stale)
              : (service.loading ? "loading…" : "no data")
            detail: root.displayCoin ? Model.formatChange(root.displayCoin.change24h) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: service.stale ? 0.5 : 1.0
            iconComponent: Component {
              CoinIcon {
                coin: root.displayCoin
                cachedFile: service.iconFor(root.displayCoin)
                size: Style.font.display
                fallbackColor: root.changeColor(root.displayCoin ? root.displayCoin.change24h : NaN, root.foreground)
                fontFamily: root.fontFamily
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {

              textFormat: Text.PlainText
              text: root.displayCoin
                ? Model.formatPrice(root.displayCoin.price, service.currency, false)
                : "—"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {

              textFormat: Text.PlainText
              visible: root.displayCoin !== null
              text: Model.changeGlyph(root.activeChartPct) + " "
                + root.chartRangeLabel + (isFinite(root.activeChartPct) ? " " + Model.formatChange(root.activeChartPct) : "")
              color: root.changeColor(root.activeChartPct, root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(6)
            }
          }

          Text {

            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: root.chartHeaderText
            color: root.changeColor(root.activeChartPct, root.foreground)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Row {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: Model.CHART_RANGES.length

              RangePill {
                required property int index
                width: Style.space(32)
                key: Model.CHART_RANGES[index].key
                label: Model.CHART_RANGES[index].label
                active: root.chartRangeKey === Model.CHART_RANGES[index].key
              }
            }

            Text {

              textFormat: Text.PlainText
              visible: text !== ""
              anchors.verticalCenter: parent.verticalCenter
              text: root.chartBusy ? "…" : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {

              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "Bar layout"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: [
                { key: "full", label: "Full" },
                { key: "compact", label: "Compact" }
              ]

              BarStylePill {
                required property var modelData
                label: modelData.label
                active: root.barStyle === modelData.key
                onClicked: root.setBarStyle(modelData.key)
              }
            }
          }

          Sparkline {
            width: parent.width
            coin: root.displayCoin
            rangeKey: root.chartRangeKey
          }

          Text {

            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: service.chartError !== "" ? "Chart: " + service.chartError : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            visible: root.displayCoin !== null
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair {
              label: "24h high"
              value: root.displayCoin ? Model.formatPrice(root.displayCoin.high24h, service.currency, root.compactPrice) : "—"
            }
            InfoPair {
              label: "24h low"
              value: root.displayCoin ? Model.formatPrice(root.displayCoin.low24h, service.currency, root.compactPrice) : "—"
            }
            InfoPair {
              label: "Market cap"
              value: root.displayCoin ? Model.formatLargeCurrency(root.displayCoin.marketCap, service.currency) : "—"
            }
            InfoPair {
              label: "24h volume"
              value: root.displayCoin ? Model.formatLargeCurrency(root.displayCoin.volume, service.currency) : "—"
            }
          }

          PanelSeparator {
            visible: root.coins.length > 1
            foreground: root.foreground
          }

          Column {
            visible: root.coins.length > 1
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "FAVORITES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: coinColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.coins

                CoinRow {
                  required property var modelData
                  required property int index
                  width: coinColumn.width
                  coin: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "ADD A COIN"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: searchField
              width: parent.width
              placeholderText: "Search any coin to add it…"
              foreground: root.foreground
              font.family: root.fontFamily

              onTextChanged: {
                root.searchIndex = 0
                if (text === "") {
                  searchDebounce.stop()
                  service.clearSearch()
                } else if (root.opened) {
                  searchDebounce.restart()
                }
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  if (text !== "") text = ""
                  else keyCatcher.forceActiveFocus()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  root.moveSearchCursor(1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  root.moveSearchCursor(-1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.activateSearch()
                  event.accepted = true
                }
              }
            }

            Text {

              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: {
                var query = Model.searchText(searchField.text)
                if (query.length < Model.MIN_SEARCH_LENGTH) return ""
                if (service.searching || searchDebounce.running) return "Searching…"
                if (service.searchError !== "") return service.searchError
                if (root.searchResults.length > 0) return ""
                return service.searchResults.length > 0 ? "Already in your favorites" : "No coins found"
              }
              color: service.searchError !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              id: searchColumn
              visible: root.searchResults.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.searchResults

                SearchRow {
                  required property var modelData
                  required property int index
                  width: searchColumn.width
                  coin: modelData
                  rowIndex: index
                }
              }
            }
          }

          Text {

            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: {
              if (service.lastError !== "") return service.lastError
              if (service.missing.length > 0) return "Unknown coin ids: " + service.missing.join(", ")
              if (!service.hasData && service.loading) return "Fetching prices…"
              return ""
            }
            color: service.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {

            textFormat: Text.PlainText
            width: parent.width
            text: "/ search · ↑↓ select · enter pin · x remove · r refresh · o coingecko"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  component Sparkline: Item {
    id: spark
    property var coin: null
    property string rangeKey: "1w"

    readonly property var chart: coin ? service.chartFor(coin, spark.rangeKey) : null

    // Keep the last good chart drawn while a new range (or coin) is being
    // fetched, and never fall back to a blank graph: the coin's free
    // sparkline data steps in immediately, so the chart only truly blanks
    // before the first market load.
    property var retainedChart: null
    property string retainedCoinId: ""
    readonly property var displayChart: {
      if (spark.chart) return spark.chart
      if (spark.retainedChart && spark.retainedChart.key === spark.rangeKey
        && spark.retainedCoinId === (spark.coin ? spark.coin.id : "")) return spark.retainedChart
      if (spark.coin) {
        var points = Model.sparklineChart(spark.coin, Model.chartRange(spark.rangeKey))
        if (points.length >= 2)
          return { key: spark.rangeKey, label: Model.chartRange(spark.rangeKey).label, points: points, pct: NaN }
      }
      return null
    }
    readonly property var series: spark.displayChart ? Model.chartSeries(spark.displayChart.points, 128) : null
    readonly property color strokeColor: root.changeColor(
      spark.displayChart && isFinite(spark.displayChart.pct) ? spark.displayChart.pct : NaN, root.foreground)

    property int hoverIndex: -1

    visible: spark.displayChart !== null
    readonly property bool loading: spark.chart === null
    implicitHeight: visible ? Style.space(104) : 0

    readonly property int seriesCount: spark.series ? spark.series.values.length : 0
    readonly property int hoverPointIndex: {
      if (spark.hoverIndex < 0 || !spark.series) return -1
      var indices = spark.series.indices
      if (spark.hoverIndex >= indices.length) return -1
      return indices[spark.hoverIndex]
    }
    readonly property var hoverPoint: {
      var i = spark.hoverPointIndex
      if (i < 0 || !spark.chart || i >= spark.chart.points.length) return null
      return spark.chart.points[i]
    }
    readonly property real hoverX: {
      if (spark.hoverIndex < 0 || spark.seriesCount < 2) return 0
      return spark.hoverIndex / (spark.seriesCount - 1) * spark.width
    }
    readonly property real hoverY: {
      var s = spark.series
      if (!s || spark.hoverIndex < 0) return 0
      var usable = Math.max(1, spark.height - 4)
      return 2 + (1 - s.values[spark.hoverIndex]) * usable
    }
    readonly property real hoverDeltaPct: {
      var p = spark.hoverPoint
      if (!p || !spark.chart || spark.chart.points.length < 2
        || !isFinite(spark.chart.points[0].p) || spark.chart.points[0].p === 0) return NaN
      return ((p.p - spark.chart.points[0].p) / spark.chart.points[0].p) * 100
    }

    onSeriesChanged: { spark.hoverIndex = -1; canvas.requestPaint() }
    onStrokeColorChanged: canvas.requestPaint()
    onHoverIndexChanged: canvas.requestPaint()
    onChartChanged: {
      if (spark.chart) {
        spark.retainedChart = spark.chart
        spark.retainedCoinId = spark.coin ? spark.coin.id : ""
      }
      canvas.requestPaint()
    }

    Canvas {
      id: canvas
      anchors.fill: parent
      antialiasing: true
      opacity: spark.loading ? 0.45 : 1

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var series = spark.series
        if (!series || width <= 0 || height <= 0) return

        var values = series.values
        var inset = 2
        var usableHeight = Math.max(1, height - inset * 2)
        var stepX = width / (values.length - 1)

        ctx.beginPath()
        for (var i = 0; i < values.length; ++i) {
          var x = i * stepX
          var y = inset + (1 - values[i]) * usableHeight
          if (i === 0) ctx.moveTo(x, y)
          else ctx.lineTo(x, y)
        }
        ctx.strokeStyle = spark.strokeColor
        ctx.lineWidth = 1.5
        ctx.lineJoin = "round"
        ctx.stroke()

        ctx.lineTo(width, height)
        ctx.lineTo(0, height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(spark.strokeColor.r, spark.strokeColor.g, spark.strokeColor.b, 0.12)
        ctx.fill()

        if (spark.hoverIndex >= 0 && spark.hoverIndex < values.length) {
          var hx = spark.hoverX
          var hy = spark.hoverY

          ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
          ctx.lineWidth = 1
          ctx.beginPath()
          ctx.moveTo(hx, inset)
          ctx.lineTo(hx, height - inset)
          ctx.moveTo(0, hy)
          ctx.lineTo(width, hy)
          ctx.stroke()

          ctx.fillStyle = spark.strokeColor
          ctx.beginPath()
          ctx.arc(hx, hy, 2.5, 0, Math.PI * 2)
          ctx.fill()
          ctx.lineWidth = 1
          ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
          ctx.beginPath()
          ctx.arc(hx, hy, 4.5, 0, Math.PI * 2)
          ctx.stroke()
        }
      }
    }

    MouseArea {
      id: sparkMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onPositionChanged: function(mouse) {
        if (spark.seriesCount < 2) { spark.hoverIndex = -1; return }
        spark.hoverIndex = Math.max(0, Math.min(spark.seriesCount - 1,
          Math.round(mouse.x / Math.max(1, width) * (spark.seriesCount - 1))))
      }
      onExited: spark.hoverIndex = -1
    }

    // Follow-the-mouse price badge: price, date/time and gain since the start
    // of the range, flipping to the other side of the point near the edges.
    Item {
      id: badge
      visible: spark.hoverPoint !== null
      z: 5
      width: Math.max(Style.space(120), badgeRow.implicitWidth + Style.space(16))
      height: badgeRow.implicitHeight + Style.space(10)

      x: {
        var x = spark.hoverIndex / Math.max(1, spark.seriesCount - 1) * spark.width
        var left = x > spark.width / 2 ? x - badge.width - Style.space(8) : x + Style.space(8)
        return Math.max(0, Math.min(spark.width - badge.width, left))
      }
      y: {
        var above = spark.hoverY - badge.height - Style.space(8)
        if (above >= Style.space(2)) return above
        return Math.min(spark.height - badge.height - Style.space(2), spark.hoverY + Style.space(10))
      }

      Rectangle {
        anchors.fill: parent
        radius: Style.space(5)
        color: Color.tooltip.background
        border.color: Color.tooltip.border
        border.width: 1
      }

      Row {
        id: badgeRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(10)

        Column {
          width: badgeRow.width - badgeDelta.implicitWidth - badgeRow.spacing - Style.space(16)
          spacing: Style.space(2)

          Text {

            textFormat: Text.PlainText
            text: {
              var p = spark.hoverPoint
              return p ? Model.formatPrice(p.p, service.currency, false) : "—"
            }
            color: Color.tooltip.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {

            textFormat: Text.PlainText
            text: {
              var p = spark.hoverPoint
              if (!p) return ""
              return Qt.formatDateTime(new Date(p.t), "d MMM · HH:mm")
            }
            color: Qt.darker(Color.tooltip.text, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          id: badgeDelta

          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: isFinite(spark.hoverDeltaPct) ? Model.formatChange(spark.hoverDeltaPct) : ""
          color: root.changeColor(spark.hoverDeltaPct, Qt.darker(Color.tooltip.text, 1.45))
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }

  component RangePill: Item {
    id: range
    property string key: ""
    property string label: ""
    property bool active: false
    signal clicked

    implicitWidth: rangeLabel.implicitWidth + Style.space(12)
    implicitHeight: Math.max(Style.space(18), rangeLabel.implicitHeight + Style.space(6))

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: range.active
        ? Style.hoverFillFor(root.foreground, Color.accent)
        : (area.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent")
    }

    Text {
      id: rangeLabel
      anchors.centerIn: parent
      text: range.label
      color: range.active ? Color.accent : (area.containsMouse ? root.foreground : root.dim)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.setChartRange(range.key)
    }
  }

  component BarStylePill: Item {
    id: stylePill
    property string label: ""
    property bool active: false
    signal clicked

    implicitWidth: styleLabel.implicitWidth + Style.space(12)
    implicitHeight: Math.max(Style.space(18), styleLabel.implicitHeight + Style.space(6))

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: stylePill.active
        ? Style.hoverFillFor(root.foreground, Color.accent)
        : (styleArea.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent")
    }

    Text {
      id: styleLabel
      anchors.centerIn: parent
      text: stylePill.label
      color: stylePill.active ? Color.accent : (styleArea.containsMouse ? root.foreground : root.dim)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    MouseArea {
      id: styleArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: stylePill.clicked()
    }
  }

  component CoinRow: CursorSurface {
    id: coinRow
    property var coin: null
    property int rowIndex: 0
    readonly property bool isPrimary: coin && coin.id === root.displayId

    hasCursor: root.cursorActive && root.coinIndex === rowIndex
    current: isPrimary
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCoinCursor(coinRow.rowIndex)
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.openCoinPage(coinRow.coin)
        else root.setPrimary(coinRow.coin ? coinRow.coin.id : "")
      }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      // Remove affordance — its own MouseArea sits above the pin/select one,
      // so clicking it never pins the row.
      Item {
        width: Style.space(16)
        height: Style.space(16)
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
          anchors.fill: parent
          radius: Style.space(3)
          color: removeArea.containsMouse ? Style.hoverFillFor(root.foreground, root.urgent) : "transparent"
        }

        Text {

          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "x"
          color: removeArea.containsMouse ? root.urgent : Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: removeArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.removeCoin(coinRow.coin ? coinRow.coin.id : "")
        }
      }

      CoinIcon {
        coin: coinRow.coin
        cachedFile: service.iconFor(coinRow.coin)
        size: Style.font.icon
        fallbackColor: coinRow.isPrimary ? root.foreground : root.dim
        fontFamily: root.fontFamily
        opacity: coinRow.isPrimary ? 1.0 : 0.75
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {

          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: coinRow.coin ? coinRow.coin.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {

          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: coinRow.coin ? coinRow.coin.symbol : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ColumnLayout {
        spacing: Style.space(1)
        Layout.alignment: Qt.AlignVCenter

        Text {

          textFormat: Text.PlainText
          Layout.alignment: Qt.AlignRight
          text: coinRow.coin ? Model.formatPrice(coinRow.coin.price, service.currency, root.compactPrice) : "—"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {

          textFormat: Text.PlainText
          Layout.alignment: Qt.AlignRight
          text: coinRow.coin ? Model.formatChange(coinRow.coin.change24h) : ""
          color: root.changeColor(coinRow.coin ? coinRow.coin.change24h : NaN, root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component SearchRow: CursorSurface {
    id: searchRow
    property var coin: null
    property int rowIndex: 0

    hasCursor: root.searchIndex === rowIndex
    current: false
    foreground: root.foreground
    implicitHeight: searchRowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.searchIndex = searchRow.rowIndex
      onClicked: root.addCoin(searchRow.coin ? searchRow.coin.id : "")
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      CoinIcon {
        coin: searchRow.coin
        cachedFile: service.iconFor(searchRow.coin)
        size: Style.font.icon
        fallbackColor: searchRow.hasCursor ? Color.accent : root.dim
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: searchRowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {

          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: searchRow.coin ? searchRow.coin.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {

          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: {
            if (!searchRow.coin) return ""
            var bits = [searchRow.coin.symbol]
            if (isFinite(searchRow.coin.rank) && searchRow.coin.rank > 0)
              bits.push("#" + Math.round(searchRow.coin.rank))
            return bits.join("  ·  ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {

        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignRight
        text: "+"
        color: searchRow.hasCursor ? Color.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  component InfoPair: Row {
    id: pair
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {

      textFormat: Text.PlainText
      id: pairLabel
      text: pair.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: Math.max(0, pair.width - pairLabel.implicitWidth - pairValue.implicitWidth - pair.spacing * 2)
      height: 1
    }

    Text {

      textFormat: Text.PlainText
      id: pairValue
      text: pair.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
