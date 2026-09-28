import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var coin: null
  // Validated local copy of the API image, from Service.iconFor(coin).
  property string cachedFile: ""
  property real size: Style.font.icon
  property color fallbackColor: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var candidates: Model.iconCandidates(coin, Qt.resolvedUrl("icons/"), cachedFile)
  readonly property string candidatesKey: candidates.join("\n")
  property int candidateIndex: 0

  onCandidatesKeyChanged: candidateIndex = 0

  implicitWidth: size
  implicitHeight: size

  Image {
    id: mark
    anchors.fill: parent
    source: root.candidateIndex < root.candidates.length ? root.candidates[root.candidateIndex] : ""
    sourceSize.width: Math.round(root.size * 2)
    sourceSize.height: Math.round(root.size * 2)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true

    onStatusChanged: if (status === Image.Error && root.candidateIndex < root.candidates.length)
      Qt.callLater(function() { root.candidateIndex++ })
  }

  Text {

    textFormat: Text.PlainText
    anchors.centerIn: parent
    visible: mark.status !== Image.Ready
    text: Model.glyphFor(root.coin)
    color: root.fallbackColor
    font.family: root.fontFamily
    font.pixelSize: root.size
  }
}
