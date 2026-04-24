
iboob 🚀

iboob is a minimalist, high-performance productivity tool for macOS designed to bridge the gap between static text and actionable intelligence. It uses advanced Accessibility hooks and a "Force Mode" to capture text from any application, providing a floating Action Bar (PopBar) for instant processing.

✨ Key Features
• Force Mode: Captures text even in "rebellious" apps (browsers, terminals, Electron) where standard selection APIs fail.
• Normal & Radial Modes: Toggle between a horizontal bar or a circular radial menu for faster muscle-memory interaction.
• Smart OCR: Built-in screen capture to extract text from images or non-selectable UI elements.
• Clipboard Protection: Automatically backs up and restores your clipboard when using Force Mode.

🛠 Technology Stack
• Language: Swift 6.0 (Concurrency / Actors).
• Frameworks: SwiftUI, AppKit, Vision (OCR), ServiceManagement (Login Items).
• Core APIs: Accessibility (AXUIElement), Quartz (CGEvent) for global event monitoring.

⸻

🔒 Setup: Accessibility Permissions
To function correctly, iboob requires Accessibility access to read the screen and simulate copy events.

1. Open System Settings.
2. Navigate to Privacy & Security → Accessibility.
3. Click the + button or toggle the switch to add iboob.
4. If it was already added but isn't working, remove it with the - button and add it again.

⸻

⌨️ Keyboard Shortcuts & AI Integration
The app is designed to trigger specific AI workflows or tools via global hotkeys. For the best experience, configure your AI automation tool (e.g., Shortcuts, Raycast, or custom scripts) to listen for the following combinations:

| Tool | Shortcut | Internal ID | Description |
| :--- | :--- | :--- | :--- |
| Show Writing Tools | ⌃⌥⌘ + ​W | w | General utility/AI agent launch. |
| Rewrite | ⌃⌥⌘ + ​R | r | Professional paraphrasing. |
| Proofread | ⌃⌥⌘ + ​P | p | Grammar and spelling check. |
| Summarize | ⌃⌥⌘ + ​S | s | Condense long texts. |
| Create Key Points | ⌃⌥⌘ + ​K | k | Extract key bullet points. |

Note: iboob activates the target app and sends these keys automatically when an action is selected from the PopBar.

⸻

🖱 Interaction Modes

1. Normal Mode (Default)
A sleek, horizontal bar appears near your cursor immediately after selecting text. Best for high-precision tool selection.

2. Radial Mode
A circular menu centered on the cursor. Designed for speed; once you learn the direction of each tool, you can trigger actions in milliseconds.
• Enable via the Status Bar Menu.

⸻

📸 OCR (Optical Character Recognition)
If text cannot be selected (inside a video, image, or protected PDF):
1. Click Capture Text (OCR) in the menu bar.
2. Select the area on the screen.
3. The text is instantly extracted, copied to your clipboard, and ready for use.

⸻

🚀 Installation
1. Move iboob​.app to your Applications folder.
2. Launch the app.
3. Enable Launch at Login from the status bar menu to keep it always ready.

⸻
Developed with focus on speed and privacy. iboob does not store your text; it only acts as a bridge between your apps.
