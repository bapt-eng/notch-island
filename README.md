<p align="center">
  <img src="https://img.shields.io/badge/macOS-Apple%20Silicon%20Liquid%20Glass-black.svg?style=for-the-badge&logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/Claude%20Code-MCP%20Ready-6366f1.svg?style=for-the-badge" alt="Claude Code">
  <img src="https://img.shields.io/badge/Cursor%20%26%20AGY-Native%20IPC-emerald.svg?style=for-the-badge" alt="Agentic IPC">
  <img src="https://img.shields.io/badge/License-MIT-amber.svg?style=for-the-badge" alt="License">
</p>

<h1 align="center">🏝️ NotchIsland 3.0 : The Liquid Glass Dynamic Island for MacBook Notch</h1>

<h3 align="center">
  Turn your useless MacBook Notch into an interactive, hardware-accelerated AI HUD for <b>Claude Code</b>, <b>Antigravity CLI</b>, <b>Cursor</b>, and macOS System Telemetry.
</h3>

<p align="center">
  <a href="#-key-features">Features</a> •
  <a href="#-claude-code--agent-integration">Claude Code Setup</a> •
  <a href="#-installation--build">Installation</a> •
  <a href="#-model-context-protocol-mcp">MCP Server</a> •
  <a href="#-architecture">Architecture</a>
</p>

---

## ⚡ What is NotchIsland ?

Most MacBook apps treat the screen notch as an annoyance to hide. **NotchIsland transforms it into your primary AI command center.**

Engineered natively in **Swift, AppKit, and Liquid Glass 3D shaders** (zero webview bloat, 0.0% idle CPU), NotchIsland hugs the physical notch with sub-millimeter precision ($179 \times 32\,\text{mm}$) and expands fluidly to deliver **real-time AI agent status**, **live coding telemetry**, **Apple Music scrubbing**, **smart MagSafe charging wattage**, and a **quick-drop file staging shelf**.

---

## 🤖 Claude Code & AI Agents Integration

> **The missing visual interface for headless terminal agents.**

When you run long agentic sessions with **Claude Code**, **Antigravity CLI**, or **Gemini**, you normally have to keep alt-tabbing to see if the model has finished thinking or requires tool permission.

**NotchIsland connects directly to Claude Code via MCP and IPC :**
- 🧠 **Live Thought Bubbles :** As Claude analyzes your codebase, status pills pulse beneath the notch.
- 🔔 **Instant Completion Banners :** When a task or unit test suite finishes, a discreet glass notification slides out.
- ⚠️ **Action Required Alert :** Flashes an amber indicator when an agent is waiting for human input.

### Add to Claude Code (`claude_desktop_config.json` or MCP Settings) :
```json
{
  "mcpServers": {
    "notch-island": {
      "command": "python3",
      "args": ["/path/to/notch-island/mcp/notch_island_server.py"]
    }
  }
}
```

Now Claude can notify you anytime using native tool calling:
```python
# What Claude Code calls internally
notch_island_notify(
    message="Build succeeded! 42 tests passing in 1.4s",
    title="Claude Code"
)
```

---

## 🌟 Key Features

* **🪟 Apple Liquid Glass 3D Material :** Custom NSView rendering authentic specular chamfers, progressive blur, and fluid spring physics inspired by Apple visionOS.
* **🎵 Native Apple Music & Spotify Bridge :** Shows currently playing track title, artist, and an interactive micro-scrubber with smooth progress bars.
* **⚡ Smart MagSafe Power Monitor :** Real-time charging wattage ($W$), battery health, and dynamic power draw tracking directly under the notch.
* **📂 Staging Shelf (File Drop Zone) :** Drag and drop files directly onto the notch to temporarily hold them before pasting into Claude, Cursor, or Slack.
* **🚀 Zero-Jank 60/120Hz ProMotion :** 100% native Cocoa code compiled with `swiftc` — no Electron, no heavy frameworks, strictly under 15MB RAM.

---

## 🛠️ Installation & Build

### Single-Command Build (Zero Dependencies) :
```bash
git clone https://github.com/bapt-eng/notch-island.git
cd notch-island

# Compile native binary with swiftc
swiftc -O src/NotchIsland.swift src/LiquidGlassView.swift src/SpotifyBridge.swift \
  -o NotchIsland -framework AppKit -framework IOKit -framework WebKit

# Run immediately
./NotchIsland
```

### CLI One-Liner Notification :
Send instant alerts from any bash script, Makefile, or Git hook:
```bash
./hooks/claude_code_hook.sh "Refactoring complete! All clean." "Antigravity Agent"
```

---

## 📡 Model Context Protocol (MCP) Tools

| Tool | Parameters | Description |
| :--- | :--- | :--- |
| `notch_island_notify` | `message` (str), `title` (str) | Expands the notch island with an elegant animated status banner |
| `notch_island_status` | none | Returns current hardware battery watts, playing track, and agent state |

---

## 📄 License

Distributed under the **MIT License**. Maintained autonomously by **Antigravity Engineering**.
