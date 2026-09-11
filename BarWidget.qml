import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "bit-dev.system-pills"
  property int cpuPercent: 0
  property int memoryPercent: 0
  property int gpuPercent: -1
  property int diskPercent: 0
  property real diskReadBps: 0
  property real diskWriteBps: 0
  property real netDownBps: 0
  property real netUpBps: 0
  property var cpuCores: []
  property var prevCores: ({})
  property real previousDiskIoMs: 0
  property real previousDiskRead: 0
  property real previousDiskWrite: 0
  property real previousDiskMs: 0
  property real diskReadTotal: 0
  property real diskWriteTotal: 0
  property real previousNetRx: 0
  property real previousNetTx: 0
  property real previousRxMs: 0
  property real previousTxMs: 0
  property real netRxTotal: 0
  property real netTxTotal: 0
  property string netIface: ""
  readonly property int intervalMs: Math.max(1000, Number(setting("refreshIntervalSec", 3)) * 1000)
  readonly property real tintOpacity: validOpacity(setting("pillOpacity", 0.24))
  readonly property color cpuAccent: validColor(setting("cpuAccent", "#F59E0B"), "#F59E0B")
  readonly property color memoryAccent: validColor(setting("memoryAccent", "#22C55E"), "#22C55E")
  readonly property color gpuAccent: validColor(setting("gpuAccent", "#8B5CF6"), "#8B5CF6")
  readonly property color diskAccent: validColor(setting("diskAccent", "#38BDF8"), "#38BDF8")
  readonly property color networkAccent: validColor(setting("networkAccent", "#EC4899"), "#EC4899")
  readonly property string diskDevice: String(setting("diskDevice", "nvme0n1"))
  readonly property string networkInterface: String(setting("networkInterface", "auto"))
  readonly property var modules: String(setting("modules", "cpu,memory,gpu,disk,network")).split(",").map(function (m) { return m.trim() })
  implicitWidth: vertical ? column.implicitWidth : row.implicitWidth
  implicitHeight: vertical ? column.implicitHeight : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  function validColor(value, fallback) { var color = String(value || ""); return /^#[0-9a-fA-F]{6}$/.test(color) ? color : fallback }
  function validOpacity(value) { var number = Number(value); return isFinite(number) ? Math.max(0.08, Math.min(0.85, number)) : 0.24 }
  function hasModule(name) { return modules.indexOf(name) >= 0 }
  function fmtBytes(bytes) {
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB"
    if (bytes >= 1024) return Math.round(bytes / 1024) + " KB"
    return Math.round(bytes) + " B"
  }
  function fmtSpeed(bytesPerSecond) {
    if (bytesPerSecond >= 1048576) return (bytesPerSecond / 1048576).toFixed(1) + " MB/s"
    if (bytesPerSecond >= 1024) return Math.round(bytesPerSecond / 1024) + " KB/s"
    return Math.round(bytesPerSecond) + " B/s"
  }
  function corePct(key, idle, total) {
    var prev = prevCores[key], pct = -1
    if (prev && total > prev.total) pct = Math.max(0, Math.min(100, Math.round((1 - (idle - prev.idle) / (total - prev.total)) * 100)))
    prevCores[key] = { total: total, idle: idle }
    return pct
  }
  function cpuTooltip() {
    var parts = ["CPU " + cpuPercent + "%"]
    for (var i = 0; i < cpuCores.length; i++) parts.push("C" + i + " " + cpuCores[i] + "%")
    return parts.join(" · ")
  }
  function parseCpu(raw) {
    var lines = String(raw || "").split("\n"), cores = []
    for (var l = 0; l < lines.length; l++) {
      var fields = lines[l].trim().split(/\s+/)
      if (fields.length < 8) continue
      var idle = Number(fields[4] || 0) + Number(fields[5] || 0), total = 0
      for (var i = 1; i < fields.length; i++) total += Number(fields[i] || 0)
      if (fields[0] === "cpu") {
        var pct = corePct("total", idle, total)
        if (pct >= 0) cpuPercent = pct
      } else if (/^cpu\d+$/.test(fields[0])) {
        var idx = parseInt(fields[0].slice(3), 10), cpct = corePct("c" + idx, idle, total)
        cores[idx] = cpct >= 0 ? cpct : (cpuCores[idx] !== undefined ? cpuCores[idx] : 0)
      }
    }
    if (cores.length) cpuCores = cores
  }
  function parseMemory(raw) {
    var lines = String(raw || "").split("\n"), total = 0, available = 0
    for (var i = 0; i < lines.length; i++) { var parts = lines[i].trim().split(/\s+/); if (parts[0] === "MemTotal:") total = Number(parts[1] || 0); else if (parts[0] === "MemAvailable:") available = Number(parts[1] || 0) }
    if (total > 0) memoryPercent = Math.max(0, Math.min(100, Math.round((1 - available / total) * 100)))
  }
  function parseGpu(raw) { var value = Number(String(raw || "").trim().split(/\s+/)[0]); gpuPercent = isFinite(value) ? Math.max(0, Math.min(100, Math.round(value))) : -1 }
  function parseDisk(raw) {
    var now = Date.now(), elapsed = previousDiskMs > 0 ? now - previousDiskMs : 0
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].trim().split(/\s+/)
      if (f.length < 13 || f[2] !== diskDevice) continue
      var ioMs = Number(f[12]) || 0, readSectors = Number(f[5]) || 0, writeSectors = Number(f[9]) || 0
      if (elapsed > 0 && previousDiskIoMs > 0) {
        diskPercent = Math.max(0, Math.min(100, Math.round((ioMs - previousDiskIoMs) / elapsed * 100)))
        diskReadBps = Math.max(0, (readSectors - previousDiskRead) * 512 / elapsed * 1000)
        diskWriteBps = Math.max(0, (writeSectors - previousDiskWrite) * 512 / elapsed * 1000)
      }
      previousDiskIoMs = ioMs; previousDiskRead = readSectors; previousDiskWrite = writeSectors
      previousDiskMs = now
      diskReadTotal = readSectors * 512; diskWriteTotal = writeSectors * 512
      return
    }
  }
  function parseNetRoute(raw) {
    if (networkInterface !== "auto") { netIface = networkInterface; return }
    var lines = String(raw || "").split("\n")
    for (var i = 1; i < lines.length; i++) {
      var f = lines[i].trim().split(/\s+/)
      if (f.length >= 2 && f[1] === "00000000") { netIface = f[0]; return }
    }
  }
  function parseNetRx(raw) {
    var now = Date.now(), elapsed = previousRxMs > 0 ? now - previousRxMs : 0
    var rx = Number(String(raw || "").trim()) || 0
    if (elapsed > 0 && previousNetRx > 0) netDownBps = Math.max(0, (rx - previousNetRx) / elapsed * 1000)
    previousNetRx = rx; previousRxMs = now; netRxTotal = rx
  }
  function parseNetTx(raw) {
    var now = Date.now(), elapsed = previousTxMs > 0 ? now - previousTxMs : 0
    var tx = Number(String(raw || "").trim()) || 0
    if (elapsed > 0 && previousNetTx > 0) netUpBps = Math.max(0, (tx - previousNetTx) / elapsed * 1000)
    previousNetTx = tx; previousTxMs = now; netTxTotal = tx
  }
  function refresh() {
    cpuFile.reload(); memoryFile.reload()
    if (hasModule("disk")) diskFile.reload()
    if (hasModule("network")) { routeFile.reload(); if (netIface) { rxFile.reload(); txFile.reload() } }
    if (!gpuProcess.running) gpuProcess.running = true
  }

  Timer { interval: root.intervalMs; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  FileView { id: cpuFile; path: "/proc/stat"; watchChanges: false; printErrors: false; onLoaded: root.parseCpu(text()) }
  FileView { id: memoryFile; path: "/proc/meminfo"; watchChanges: false; printErrors: false; onLoaded: root.parseMemory(text()) }
  FileView { id: diskFile; path: "/proc/diskstats"; watchChanges: false; printErrors: false; onLoaded: root.parseDisk(text()) }
  FileView { id: routeFile; path: "/proc/net/route"; watchChanges: false; printErrors: false; onLoaded: root.parseNetRoute(text()) }
  FileView { id: rxFile; path: root.netIface ? "/sys/class/net/" + root.netIface + "/statistics/rx_bytes" : ""; watchChanges: false; printErrors: false; onLoaded: root.parseNetRx(text()) }
  FileView { id: txFile; path: root.netIface ? "/sys/class/net/" + root.netIface + "/statistics/tx_bytes" : ""; watchChanges: false; printErrors: false; onLoaded: root.parseNetTx(text()) }
  Process {
    id: gpuProcess
    command: ["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseGpu(text)
    }
    onExited: function(code) {
      if (code !== 0) root.gpuPercent = -1
    }
  }

  Row { id: row; visible: !root.vertical; spacing: Style.space(3)
    SystemPill { visible: root.hasModule("cpu"); bar: root.bar; metricName: "CPU"; value: root.cpuPercent + "%"; tooltipText: root.cpuTooltip(); iconSource: Qt.resolvedUrl("assets/cpu.svg"); accent: root.cpuAccent; tintOpacity: root.tintOpacity; displayMode: "full" }
    SystemPill { visible: root.hasModule("memory"); bar: root.bar; metricName: "Memory"; value: root.memoryPercent + "%"; iconSource: Qt.resolvedUrl("assets/memory.svg"); accent: root.memoryAccent; tintOpacity: root.tintOpacity; displayMode: "full" }
    SystemPill { visible: root.hasModule("gpu"); bar: root.bar; metricName: "GPU"; value: root.gpuPercent < 0 ? "—" : root.gpuPercent + "%"; iconSource: Qt.resolvedUrl("assets/gpu.svg"); accent: root.gpuAccent; tintOpacity: root.tintOpacity; displayMode: "full" }
    SystemPill { visible: root.hasModule("disk"); bar: root.bar; metricName: "Disk"; value: root.diskPercent + "%"; tooltipText: "Disk " + root.diskDevice + ": " + root.diskPercent + "% busy · R " + root.fmtSpeed(root.diskReadBps) + " · W " + root.fmtSpeed(root.diskWriteBps) + " · total R " + root.fmtBytes(root.diskReadTotal) + " / W " + root.fmtBytes(root.diskWriteTotal); iconSource: Qt.resolvedUrl("assets/disk.svg"); accent: root.diskAccent; tintOpacity: root.tintOpacity; displayMode: "full" }
    SystemPill { visible: root.hasModule("network"); bar: root.bar; metricName: "Network"; value: "↓" + root.fmtSpeed(root.netDownBps).replace(" ", "") + " ↑" + root.fmtSpeed(root.netUpBps).replace(" ", ""); tooltipText: (root.netIface || "n/a") + ": ↓ " + root.fmtSpeed(root.netDownBps) + " · ↑ " + root.fmtSpeed(root.netUpBps) + " · total ↓ " + root.fmtBytes(root.netRxTotal) + " / ↑ " + root.fmtBytes(root.netTxTotal); showIcon: false; accent: root.networkAccent; tintOpacity: root.tintOpacity; displayMode: "full" }
  }
  Column { id: column; visible: root.vertical; spacing: Style.space(3)
    SystemPill { visible: root.hasModule("cpu"); bar: root.bar; metricName: "CPU"; value: root.cpuPercent + "%"; tooltipText: root.cpuTooltip(); iconSource: Qt.resolvedUrl("assets/cpu.svg"); accent: root.cpuAccent; tintOpacity: root.tintOpacity; displayMode: "minimal"; width: root.barSize }
    SystemPill { visible: root.hasModule("memory"); bar: root.bar; metricName: "Memory"; value: root.memoryPercent + "%"; iconSource: Qt.resolvedUrl("assets/memory.svg"); accent: root.memoryAccent; tintOpacity: root.tintOpacity; displayMode: "minimal"; width: root.barSize }
    SystemPill { visible: root.hasModule("gpu"); bar: root.bar; metricName: "GPU"; value: root.gpuPercent < 0 ? "—" : root.gpuPercent + "%"; iconSource: Qt.resolvedUrl("assets/gpu.svg"); accent: root.gpuAccent; tintOpacity: root.tintOpacity; displayMode: "minimal"; width: root.barSize }
    SystemPill { visible: root.hasModule("disk"); bar: root.bar; metricName: "Disk"; value: root.diskPercent + "%"; tooltipText: "Disk " + root.diskDevice + ": " + root.diskPercent + "% busy · R " + root.fmtSpeed(root.diskReadBps) + " · W " + root.fmtSpeed(root.diskWriteBps) + " · total R " + root.fmtBytes(root.diskReadTotal) + " / W " + root.fmtBytes(root.diskWriteTotal); iconSource: Qt.resolvedUrl("assets/disk.svg"); accent: root.diskAccent; tintOpacity: root.tintOpacity; displayMode: "minimal"; width: root.barSize }
    SystemPill { visible: root.hasModule("network"); bar: root.bar; metricName: "Network"; value: "↓" + root.fmtSpeed(root.netDownBps).replace(" ", "") + " ↑" + root.fmtSpeed(root.netUpBps).replace(" ", ""); tooltipText: (root.netIface || "n/a") + ": ↓ " + root.fmtSpeed(root.netDownBps) + " · ↑ " + root.fmtSpeed(root.netUpBps) + " · total ↓ " + root.fmtBytes(root.netRxTotal) + " / ↑ " + root.fmtBytes(root.netTxTotal); showIcon: false; accent: root.networkAccent; tintOpacity: root.tintOpacity; displayMode: "minimal"; width: root.barSize }
  }
}
