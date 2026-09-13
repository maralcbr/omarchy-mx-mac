import QtQuick
import QtTest

TestCase {
  name: "PasswordFeedback"
  when: windowShown
  visible: true
  width: 640
  height: 480
  property var userModel: ({lastUser: "fixture"})
  property var sessionModel: ({lastIndex: 0, rowCount: function() { return 0 }})
  property QtObject sddm: QtObject {
    signal loginFailed()
    signal loginSucceeded()
  }
  function findInput(item) {
    if (item.echoMode !== undefined) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = findInput(item.children[i])
      if (found) return found
    }
    return null
  }
  function test_masking() {
    var component = Qt.createComponent("../../../default/sddm/omarchy/Main.qml")
    compare(component.status, Component.Ready, component.errorString())
    var theme = component.createObject(this)
    verify(theme !== null)
    var input = findInput(theme)
    verify(input !== null)
    input.forceActiveFocus()
    for (var key of [Qt.Key_S, Qt.Key_A, Qt.Key_M, Qt.Key_P, Qt.Key_L, Qt.Key_E]) keyClick(key)
    compare(input.text, "sample")
    compare(input.displayText, "\u2022\u2022\u2022\u2022\u2022\u2022")
    verify(input.color.a > 0)
    keyClick(Qt.Key_Backspace)
    compare(input.displayText.length, 5)
    sddm.loginFailed()
    compare(input.text, "")
    compare(theme.loginFailed, true)
    keyClick(Qt.Key_A)
    compare(theme.loginFailed, false)
    input.text = ""
    input.focus = false
    mouseClick(theme, 10, 10)
    tryCompare(input, "activeFocus", true)
    theme.destroy()
  }
}
