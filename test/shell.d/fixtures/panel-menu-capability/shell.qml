import QtQuick
import QtQml.Models
import Quickshell
import "services"

// Drives the production panel-delegate manifest binding and app-library grant
// across a real Instantiator model boundary. The __MARKERS__ are filled from
// shell/shell.qml by panel-menu-capability-test.sh.
ShellRoot {
  id: shell

  property var pluginRegistry: ({ installedPlugins: {
    "example.menu": { id: "example.menu", kinds: ["menu", "bar-widget"],
      omarchy: { clonedFrom: "omarchy.menu" } },
    "example.panel": { id: "example.panel", kinds: ["panel"] },
    "example.overlay": { id: "example.overlay", kinds: ["overlay"] }
  } })
  // Same shape as computePanelEntries(): each entry carries the manifest
  // object, plus one stale entry whose plugin has left the registry.
  property var panelEntries: Object.keys(pluginRegistry.installedPlugins).map(function(id) {
    return { id: id, manifest: shell.pluginRegistry.installedPlugins[id] }
  }).concat([{ id: "example.removed", manifest: { id: "example.removed", kinds: ["menu"] } }])
  property var failures: []
  property int checked: 0
  property bool boundaryConverts: false

  // Filled from shell.qml by the test runner, not a copy of the implementation.
  __MANIFEST_HAS_KIND__

  PluginAppLibraryApi {
    id: menuLibrary
    ownerPluginId: "example.menu"
    _sortedEntries: function(query) { return [{ entry: { id: "example-app", name: "Example App" } }] }
  }

  function pluginAppLibraryFor(cacheKey, key) { return menuLibrary }

  Component { id: apiComponent; PluginShellApi {} }

  function check(manifest, pluginId, rawKinds) {
    if (rawKinds && !Array.isArray(rawKinds)) shell.boundaryConverts = true
    var key = pluginId
    var cacheKey = key
    var api = apiComponent.createObject(null, {
      pluginId: key,
      appLibrary: __APP_LIBRARY_GRANT__
    })
    var expected = pluginId === "example.menu"
    var granted = !!api && !!api.appLibrary
    if (granted !== expected) failures.push(pluginId + ": wrong app-library grant (" + granted + ")")
    if (granted && api.appLibrary.sortedEntries("")[0].entry.id !== "example-app")
      failures.push(pluginId + ": app entries unavailable")
    if (api) api.destroy()
    checked += 1
  }

  Instantiator {
    model: shell.panelEntries
    delegate: QtObject {
      required property var modelData
      readonly property string pluginId: modelData.id
      __PANEL_MANIFEST_BINDING__
      Component.onCompleted: shell.check(manifest, pluginId, modelData.manifest.kinds)
    }
  }

  Timer {
    interval: 50
    running: true
    onTriggered: {
      if (shell.checked !== 4) shell.failures.push("every panel entry must be checked, got " + shell.checked)
      if (shell.failures.length) console.error("PANEL_MENU_FAIL", JSON.stringify(shell.failures))
      else console.log("PANEL_MENU_OK boundaryConverts=" + shell.boundaryConverts)
      Qt.quit()
    }
  }
}
