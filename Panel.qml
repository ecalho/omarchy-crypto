import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "thales.crypto"
  ipcTarget: "thales.crypto"
  manageIpc: false

  property int coinIndex: 0
  property bool cursorActive: false

  readonly property bool vertical: bar ? bar.vertical : false

  readonly property var coins: service.coins
  readonly property string displayId: Model.resolvePrimaryId(service.ids, setting("primary", ""))
  readonly property var displayCoin: Model.findCoin(coins, displayId)
  readonly property var selectedCoin: coins.length > 0
    ? coins[Math.max(0, Math.min(coinIndex, coins.length - 1))]
    : null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool showIcon: setting("showIcon", true) === true
  readonly property bool showSymbol: setting("showSymbol", true) === true
  readonly property bool showChange: setting("showChange", true) === true
  readonly property bool compactPrice: setting("compactPrice", false) === true
  readonly property bool colorizeChange: setting("colorizeChange", true) === true
  readonly property int rotateSeconds: {
    var seconds = Math.floor(Number(setting("rotateSeconds", 10)))
    if (!isFinite(seconds) || seconds <= 0) return 0
    return Math.max(2, Math.min(3600, seconds))
  }

  readonly property var labelOptions: ({
    currency: service.currency,
    showSymbol: root.showSymbol,
    showChange: root.showChange,
    compactPrice: root.compactPrice
  })

  property real pillOpacity: 1.0

  readonly property string barText: Model.barLabel(displayCoin, labelOptions)
  readonly property var barLines: Model.verticalBarLines(displayCoin, labelOptions)
  readonly property int displayDirection: displayCoin ? Model.changeDirection(displayCoin.change24h) : 0

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
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.primary = id

    var peers = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    for (var i = 0; i < peers.length; ++i) {
      if (peers[i] && peers[i] !== root && "settings" in peers[i]) peers[i].settings = entry
    }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function cyclePrimary(step) {
    root.setPrimary(Model.stepPrimaryId(service.ids, root.displayId, step))
  }

  function openCoinPage(coin) {
    if (!coin || !root.bar) return
    root.bar.run("xdg-open " + root.bar.shellQuote(Model.coinPageUrl(coin.id)))
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
    var item = coinColumn.children[coinIndex]
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
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
    var index = Model.coinIndex(coins, displayId)
    coinIndex = index === -1 ? 0 : index
    if (panelFlick) panelFlick.contentY = 0
    service.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
  }

  Connections {
    target: service
    function onCoinsChanged() { root.ensureCursor() }
  }

  Timer {
    interval: root.rotateSeconds * 1000
    repeat: true
    running: root.rotateSeconds > 0 && !root.opened && !pillHover.hovered
    onTriggered: pillSwap.restart()
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
        size: root.pillIconSize
        fallbackColor: button.labelColor
        fontFamily: button.fontFamily
      }

      Text {
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
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (key === "r") root.refresh()
        else if (key === "o") root.openCoinPage(root.cursorActive ? root.selectedCoin : root.displayCoin)
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
            title: root.selectedCoin ? root.selectedCoin.name : "Crypto"
            meta: root.selectedCoin
              ? Model.heroMeta(root.selectedCoin, service.currency, service.lastUpdated, service.stale)
              : (service.loading ? "loading…" : "no data")
            detail: root.selectedCoin ? Model.formatChange(root.selectedCoin.change24h) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: service.stale ? 0.5 : 1.0
            iconComponent: Component {
              CoinIcon {
                coin: root.selectedCoin
                size: Style.font.display
                fallbackColor: root.changeColor(root.selectedCoin ? root.selectedCoin.change24h : NaN, root.foreground)
                fontFamily: root.fontFamily
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: root.selectedCoin
                ? Model.formatPrice(root.selectedCoin.price, service.currency, false)
                : "—"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              visible: root.selectedCoin !== null
              text: Model.changeGlyph(root.selectedCoin ? root.selectedCoin.change24h : NaN) + " 24h"
              color: root.changeColor(root.selectedCoin ? root.selectedCoin.change24h : NaN, root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(6)
            }
          }

          Sparkline {
            width: parent.width
            coin: root.selectedCoin
          }

          Column {
            visible: root.selectedCoin !== null
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair {
              label: "24h high"
              value: root.selectedCoin ? Model.formatPrice(root.selectedCoin.high24h, service.currency, root.compactPrice) : "—"
            }
            InfoPair {
              label: "24h low"
              value: root.selectedCoin ? Model.formatPrice(root.selectedCoin.low24h, service.currency, root.compactPrice) : "—"
            }
            InfoPair {
              label: "Market cap"
              value: root.selectedCoin ? Model.formatLargeCurrency(root.selectedCoin.marketCap, service.currency) : "—"
            }
            InfoPair {
              label: "24h volume"
              value: root.selectedCoin ? Model.formatLargeCurrency(root.selectedCoin.volume, service.currency) : "—"
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

          Text {
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
            width: parent.width
            text: "↑↓ select · enter pin · r refresh · o coingecko"
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
    readonly property var series: coin ? Model.sparklinePoints(coin.sparkline, 96) : null
    readonly property color strokeColor: root.changeColor(
      coin ? Model.sparklineChange(coin.sparkline) : NaN, root.foreground)

    visible: series !== null
    implicitHeight: visible ? Style.space(52) : 0

    onSeriesChanged: canvas.requestPaint()
    onStrokeColorChanged: canvas.requestPaint()

    Canvas {
      id: canvas
      anchors.fill: parent
      antialiasing: true

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
      }
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

      CoinIcon {
        coin: coinRow.coin
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
          Layout.fillWidth: true
          text: coinRow.coin ? coinRow.coin.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
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
          Layout.alignment: Qt.AlignRight
          text: coinRow.coin ? Model.formatPrice(coinRow.coin.price, service.currency, root.compactPrice) : "—"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          Layout.alignment: Qt.AlignRight
          text: coinRow.coin ? Model.formatChange(coinRow.coin.change24h) : ""
          color: root.changeColor(coinRow.coin ? coinRow.coin.change24h : NaN, root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
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
      id: pairValue
      text: pair.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
