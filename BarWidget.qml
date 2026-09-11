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
  property real memoryUsedBytes: 0
  property real memoryTotalBytes: 0
  property real memoryFreeBytes: 0
  property int diskPercent: 0
  property real diskReadBps: 0
  property real diskWriteBps: 0
  property real diskUsedBytes: 0
  property real diskTotalBytes: 0
  property real diskFreeBytes: 0
  property var cpuCores: []
  property var prevCores: ({})
  property real previousDiskIoMs: 0
  property real previousDiskRead: 0
  property real previousDiskWrite: 0
  property real previousDiskMs: 0
  readonly property int intervalMs: Math.max(1000, Number(setting("refreshIntervalSec", 3)) * 1000)
  readonly property real tintOpacity: validOpacity(setting("pillOpacity", 0.24))
  readonly property color cpuAccent: validColor(setting("cpuAccent", "#F59E0B"), "#F59E0B")
  readonly property color memoryAccent: validColor(setting("memoryAccent", "#22C55E"), "#22C55E")
  readonly property color diskAccent: validColor(setting("diskAccent", "#38BDF8"), "#38BDF8")
  readonly property string diskDevice: String(setting("diskDevice", "nvme0n1"))
  readonly property var modules: String(setting("modules", "cpu,memory,disk")).split(",").map(function (m) { return m.trim() })
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
  function cpuBar(pct) {
    var cells = Math.max(0, Math.min(10, Math.round(pct / 10))), s = ""
    for (var i = 0; i < 10; i++) s += i < cells ? "█" : "░"
    return s
  }
  function cpuTooltip() {
    var lines = ["CPU " + cpuPercent + "% · " + cpuCores.length + " cores"]
    for (var i = 0; i < cpuCores.length; i++) {
      var label = "C" + (i < 10 ? "0" + i : i), pct = cpuCores[i]
      lines.push(label + " " + (pct < 10 ? "0" + pct : pct) + "% " + cpuBar(pct))
    }
    return lines.join("\n")
  }
  function memoryTooltip() {
    return "Memory " + memoryPercent + "% · " + fmtBytes(memoryUsedBytes) + "/" + fmtBytes(memoryTotalBytes) + " (" + fmtBytes(memoryFreeBytes) + " free)"
  }
  function diskTooltip() {
    return "Disk " + diskDevice + ": " + diskPercent + "% busy · R " + fmtSpeed(diskReadBps) + " · W " + fmtSpeed(diskWriteBps) + " · " + fmtBytes(diskUsedBytes) + "/" + fmtBytes(diskTotalBytes) + " (" + fmtBytes(diskFreeBytes) + " free)"
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
    if (total > 0) {
      memoryPercent = Math.max(0, Math.min(100, Math.round((1 - available / total) * 100)))
      memoryTotalBytes = total * 1024; memoryFreeBytes = available * 1024; memoryUsedBytes = Math.max(0, (total - available) * 1024)
    }
  }
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
      return
    }
  }
  function parseDf(raw) {
    var lines = String(raw || "").trim().split("\n")
    if (lines.length < 2) return
    var f = lines[1].trim().split(/\s+/)
    if (f.length < 3) return
    var used = Number(f[0]) || 0, size = Number(f[1]) || 0, avail = Number(f[2]) || 0
    if (size > 0) { diskUsedBytes = used; diskTotalBytes = size; diskFreeBytes = avail }
  }
  function refresh() {
    cpuFile.reload(); memoryFile.reload()
    if (hasModule("disk")) { diskFile.reload(); if (!dfProcess.running) dfProcess.running = true }
  }

  Timer { interval: root.intervalMs; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  FileView { id: cpuFile; path: "/proc/stat"; watchChanges: false; printErrors: false; onLoaded: root.parseCpu(text()) }
  FileView { id: memoryFile; path: "/proc/meminfo"; watchChanges: false; printErrors: false; onLoaded: root.parseMemory(text()) }
  FileView { id: diskFile; path: "/proc/diskstats"; watchChanges: false; printErrors: false; onLoaded: root.parseDisk(text()) }
  Process {
    id: dfProcess
    command: ["df", "-B1", "--output=used,size,avail", "/"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseDf(text) }
  }

  Row { id: row; visible: !root.vertical; spacing: Style.space(3)
    SystemPill { visible: root.hasModule("cpu"); bar: root.bar; metricName: "CPU"; value: root.cpuPercent + "%"; tooltipText: root.cpuTooltip(); iconSource: Qt.resolvedUrl("assets/cpu.svg"); accent: root.cpuAccent; tintOpacity: root.tintOpacity; displayMode: "full" }
    SystemPill { visible: root.hasModule("memory"); bar: root.bar; metricName: "Memory"; value: root.memoryPercent + "%"; tooltipText: root.memoryTooltip(); iconSource: Qt.resolvedUrl("assets/memory.svg"); accent: root.memoryAccent; tintOpacity: root.tintOpacity; displayMode: "full" }
    SystemPill { visible: root.hasModule("disk"); bar: root.bar; metricName: "Disk"; value: root.diskPercent + "%"; tooltipText: root.diskTooltip(); iconSource: Qt.resolvedUrl("assets/disk.svg"); accent: root.diskAccent; tintOpacity: root.tintOpacity; displayMode: "full" }
  }
  Column { id: column; visible: root.vertical; spacing: Style.space(3)
    SystemPill { visible: root.hasModule("cpu"); bar: root.bar; metricName: "CPU"; value: root.cpuPercent + "%"; tooltipText: root.cpuTooltip(); iconSource: Qt.resolvedUrl("assets/cpu.svg"); accent: root.cpuAccent; tintOpacity: root.tintOpacity; displayMode: "minimal"; width: root.barSize }
    SystemPill { visible: root.hasModule("memory"); bar: root.bar; metricName: "Memory"; value: root.memoryPercent + "%"; tooltipText: root.memoryTooltip(); iconSource: Qt.resolvedUrl("assets/memory.svg"); accent: root.memoryAccent; tintOpacity: root.tintOpacity; displayMode: "minimal"; width: root.barSize }
    SystemPill { visible: root.hasModule("disk"); bar: root.bar; metricName: "Disk"; value: root.diskPercent + "%"; tooltipText: root.diskTooltip(); iconSource: Qt.resolvedUrl("assets/disk.svg"); accent: root.diskAccent; tintOpacity: root.tintOpacity; displayMode: "minimal"; width: root.barSize }
  }
}
