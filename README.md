<h1 align="center">
  iboob
</h1>

<p align="center">
  <b>A minimalist, high-performance productivity tool for macOS designed to bridge the gap between static text and actionable intelligence.</b>
</p>

> ◈ **iboob** uses advanced Accessibility hooks and a "Force Mode" to capture text from any application, providing a floating Action Bar (PopBar) for instant processing.

---

### ✦ Key Features

◦ **Force Mode:** Captures text even in "rebellious" apps (browsers, terminals, Electron) where standard selection APIs fail.  
◦ **Normal & Radial Modes:** Toggle between a horizontal bar or a circular radial menu for faster muscle-memory interaction.  
◦ **Smart OCR:** Built-in screen capture to extract text from images or non-selectable UI elements.  
◦ **Clipboard Protection:** Automatically backs up and restores your clipboard when using Force Mode.

### ⬢ Technology Stack

◦ **Language:** `Swift 6.0` (Concurrency / Actors).  
◦ **Frameworks:** `SwiftUI`, `AppKit`, `Vision` (OCR), `ServiceManagement` (Login Items).  
◦ **Core APIs:** `Accessibility` (`AXUIElement`), `Quartz` (`CGEvent`) for global event monitoring.

---

### ⌘ Keyboard Shortcuts & AI Integration

The app is designed to trigger specific AI workflows or tools via global hotkeys. For the best experience, configure your AI automation tool (e.g., Shortcuts, Raycast, or custom scripts) to listen for the following combinations:

| Tool | Shortcut | Internal ID | Description |
| :--- | :--- | :--- | :--- |
| **Show Writing Tools** | `⌃⌥⌘ + W` | `w` | General utility/AI agent launch. |
| **Rewrite** | `⌃⌥⌘ + R` | `r` | Professional paraphrasing. |
| **Proofread** | `⌃⌥⌘ + P` | `p` | Grammar and spelling check. |
| **Summarize** | `⌃⌥⌘ + S` | `s` | Condense long texts. |
| **Create Key Points** | `⌃⌥⌘ + K` | `k` | Extract key bullet points. |

---

### ⌖ Interaction Modes

<div align="center">
  <table style="margin-left: auto; margin-right: auto;">
    <tr>
      <td align="center" width="400"><b>Normal Mode</b></td>
      <td align="center" width="400"><b>Radial Mode</b></td>
    </tr>
    <tr>
      <td align="center">
        <img src="https://github.com/user-attachments/assets/b38632b7-d123-4632-9188-60bd29d118fd" width="350">
        <br><i>Sleek, high-precision horizontal bar.</i>
      </td>
      <td align="center">
        <img src="https://github.com/user-attachments/assets/a913317f-63bb-48b2-a304-87588c97435d" width="350">
        <br><i>Circular menu for extreme speed.</i>
      </td>
    </tr>
  </table>
</div>

---

### ⌬ OCR (Optical Character Recognition)

If text cannot be selected (inside a video, image, or protected PDF):
1. Click **Capture Text (OCR)** in the menu bar.
2. Select the area on the screen.
3. The text is instantly extracted, copied to your clipboard, and ready for use.

### ⚙︎ Setup: Accessibility Permissions

To function correctly, iboob requires Accessibility access to read the screen and simulate copy events.

1. Open **System Settings** > **Privacy & Security** > **Accessibility**.
2. Click the `+` button or toggle the switch to add **iboob**.
3. *Note:* If it was already added but isn't working, remove it with the `-` button and add it again.

---

### ⎗ Installation

1. Move `iboob.app` to your **Applications** folder.
2. Launch the app.
3. Enable **Launch at Login** from the status bar menu to keep it always ready.

---

<p align="center">
  <i>Developed with a focus on speed and privacy. <b>iboob does not store your text</b>; it only acts as a fast, native bridge between your apps.</i>
</p>
