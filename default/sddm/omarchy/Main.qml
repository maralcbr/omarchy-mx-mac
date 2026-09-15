import QtQuick 2.0
import QtQuick.Window 2.15 as QtWindow
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  property string currentUser: userModel.lastUser
  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      password.text = ""
      root.loginFailed = true
      password.forceActiveFocus()
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: password.forceActiveFocus()
  }

  QtWindow.Window.onActiveChanged: {
    if (QtWindow.Window.active)
      password.forceActiveFocus()
  }

  Column {
    anchors.centerIn: parent
    spacing: 40

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Text {
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: Text.AlignVCenter
          visible: password.text.length === 0
          text: root.QtWindow.Window.active ? "Password" : "Click to type here"
          color: "#9aa5ce"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 18
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "\u2022"
          passwordMaskDelay: 0
          color: "#c0caf5"
          selectionColor: "#414868"
          selectedTextColor: "#c0caf5"
          clip: true
          cursorVisible: activeFocus && root.QtWindow.Window.active
          focus: true

          onTextChanged: root.loginFailed = false

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              sddm.login(root.currentUser, password.text, root.sessionIndex)
              event.accepted = true
            }
          }
        }
      }
    }

  }

  Component.onCompleted: password.forceActiveFocus()
}
