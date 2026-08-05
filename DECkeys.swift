// DECkeys — a floating DEC keypad that never takes focus.
//
// Copyright (C) 2026 Scott Klein
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 2 as published
// by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.  You should have received a copy of the GPL along with
// this program; if not, see <https://www.gnu.org/licenses/>.
//
// Clicking a button sends to whatever application is frontmost, like the macOS
// Accessibility Keyboard but for vintage terminal keys a laptop doesn't have.
// The layout is data: see profile.json, which is read at launch, so adding keys
// needs no rebuild.  Test what actually arrives with `cat -v` in the target.

import AppKit
import ApplicationServices

// MARK: - profile

struct KeySpec: Codable {
    let label: String
    var row: Int? = 0
    var gold: Bool? = false
    var keycode: Int? = nil     // macOS virtual keycode, decimal
    var bytes: String? = nil    // escape sequence, with \e for ESC
    /// Cap width in units, as on the real keyboard — Do is a double-wide key.
    var span: Int? = 1
    /// DEC moulded the function row and the editing keypad in a darker grey
    /// than the alphanumerics and the numeric keypad. Cosmetic, but it is how
    /// you find a key group without reading it.
    var dark: Bool? = false
    /// Not a key on a real LK201 — a convenience (Ctrl-Z and friends). Painted
    /// differently so the panel never pretends it is reproducing hardware.
    var conv: Bool? = false
    /// Explicit grid position and vertical extent. Needed for the numeric
    /// keypad, where 0 is double-wide and Enter is double-HIGH — without
    /// these the last two rows cannot be shaped like the real thing.
    var col: Int? = nil
    var rowspan: Int? = 1
    /// A legend that belongs to the KEY, not to an application — "Help" and
    /// "Do" are what DEC called F15 and F16 everywhere. Application-specific
    /// legends live in `legends` sets and take precedence over this.
    var legend: String? = nil
}

/// What an application does with a key — the second and third legends printed
/// on a real DEC keycap. Application-specific: the same KP4 is "Word" to
/// WPS-PLUS and "ADVANCE" to EDT, which is why these are sets rather than
/// properties of the key.
struct Legend: Codable {
    var legend: String? = nil    // unshifted function (black secondary legend)
    var gold: String? = nil      // Gold-prefixed function (the red legend)
    /// Paint this cap gold. Belongs to the SET, not the key: with no overlay
    /// selected PF1 is just PF1 — "Gold" is what an application makes of it.
    var goldCap: Bool? = nil
    /// Full wording for the tooltip when the cap legend has to be abbreviated
    /// to fit — "PREVIOUSLY DISPLAYED NOTE" does not go on a 54-point key.
    var note: String? = nil
}

struct Profile: Codable {
    let title: String
    var mode: String? = "bytes"
    var keyWidth: Double? = nil      // point size of a cap; tune without rebuilding
    var keyHeight: Double? = nil
    var gap: Double? = nil
    var legendSet: String? = nil                       // which set to display
    var legends: [String: [String: Legend]]? = nil     // set -> key label -> legend
    let keys: [KeySpec]
}

/// `\e` -> ESC and friends. Hand-editing "" in JSON is miserable.
func expand(_ s: String) -> String {
    var out = "", it = s.makeIterator()
    var pending: Character? = nil
    while let c = pending ?? it.next() {
        pending = nil
        guard c == "\\", let n = it.next() else { out.append(c); continue }
        switch n {
        case "e": out.append("\u{1B}")
        case "r": out.append("\r")
        case "n": out.append("\n")
        case "t": out.append("\t")
        case "\\": out.append("\\")
        case "c":                       // \cZ -> Ctrl-Z
            if let l = it.next(), let a = l.uppercased().unicodeScalars.first,
               a.value >= 64, a.value <= 95 {
                out.unicodeScalars.append(Unicode.Scalar(a.value - 64)!)
            }
        default: out.append(c); pending = n
        }
    }
    return out
}

/// profile.json sits beside the .app so it can be edited without touching the
/// bundle; the copy inside Resources is the fallback/default.
func loadProfile() -> (Profile, String) {
    var tried: [String] = []
    var candidates: [URL] = []
    // ~/.config/deckeys/profile.json first, so the app can be installed in
    // /Applications and still have an editable profile outside the bundle --
    // anything inside DECkeys.app is overwritten by the next build.
    let cfg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        .map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
    candidates.append(cfg.appendingPathComponent("deckeys/profile.json"))
    let bundle = Bundle.main.bundleURL
    candidates.append(bundle.deletingLastPathComponent().appendingPathComponent("profile.json"))
    if let r = Bundle.main.url(forResource: "profile", withExtension: "json") { candidates.append(r) }

    for url in candidates {
        tried.append(url.path)
        if let data = try? Data(contentsOf: url),
           let p = try? JSONDecoder().decode(Profile.self, from: data) {
            return (p, url.path)
        }
    }
    let fallback = Profile(title: "DECkeys (no profile)", mode: "bytes", keys: [])
    return (fallback, "none of: " + tried.joined(separator: ", "))
}

enum SendMode { case keycode, bytes }
var sendMode: SendMode = .bytes

// MARK: - sending

/// Post a real key press. `.maskNumericPad` matters: macOS flags genuine
/// keypad keys with it and clients use it to decide a key is "keypad" at all.
func postKeycode(_ code: CGKeyCode) {
    let src = CGEventSource(stateID: .hidSystemState)
    guard let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
          let up   = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
    else { return }
    down.flags = .maskNumericPad
    up.flags   = .maskNumericPad
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

/// ASCII -> (US-layout virtual keycode, needs shift).  Enough to spell any
/// terminal escape sequence: ESC, the letters, digits, [ ] ; ~ etc.
let ASCII_KEYS: [Character: (CGKeyCode, Bool)] = {
    var m: [Character: (CGKeyCode, Bool)] = [:]
    let lower: [(Character, CGKeyCode)] = [
        ("a",0x00),("s",0x01),("d",0x02),("f",0x03),("h",0x04),("g",0x05),
        ("z",0x06),("x",0x07),("c",0x08),("v",0x09),("b",0x0B),("q",0x0C),
        ("w",0x0D),("e",0x0E),("r",0x0F),("y",0x10),("t",0x11),("o",0x1F),
        ("u",0x20),("i",0x22),("p",0x23),("l",0x25),("j",0x26),("k",0x28),
        ("n",0x2D),("m",0x2E),
    ]
    for (c, k) in lower {
        m[c] = (k, false)
        m[Character(c.uppercased())] = (k, true)
    }
    let plain: [(Character, CGKeyCode)] = [
        ("1",0x12),("2",0x13),("3",0x14),("4",0x15),("5",0x17),("6",0x16),
        ("7",0x1A),("8",0x1C),("9",0x19),("0",0x1D),
        ("[",0x21),("]",0x1E),(";",0x29),("'",0x27),(",",0x2B),(".",0x2F),
        ("/",0x2C),("\\",0x2A),("-",0x1B),("=",0x18),("`",0x32),(" ",0x31),
        ("\u{1B}",0x35),   // ESC
        ("\r",0x24),("\t",0x30),
    ]
    for (c, k) in plain { m[c] = (k, false) }
    let shifted: [(Character, CGKeyCode)] = [
        ("~",0x32),("!",0x12),("@",0x13),("#",0x14),("$",0x15),("%",0x17),
        ("^",0x16),("&",0x1A),("*",0x1C),("(",0x19),(")",0x1D),
        ("{",0x21),("}",0x1E),(":",0x29),("\"",0x27),("<",0x2B),(">",0x2F),
        ("?",0x2C),("|",0x2A),("_",0x1B),("+",0x18),
    ]
    for (c, k) in shifted { m[c] = (k, true) }
    return m
}()

/// Post a string as genuine keystrokes.
///
/// WHY NOT keyboardSetUnicodeString (tried and abandoned 2026-08-04): with a
/// real event source macOS re-translates the virtual keycode through the
/// current layout and that beats the unicode string — keycode 0 is 'a' on a US
/// layout, so every button typed "a".  Passing a nil source did not fix it
/// either.  Pressing the actual keys cannot lose this argument: the client sees
/// exactly what a person at the keyboard would produce.
///
/// Cost: it assumes a US layout.  Fine for escape sequences, which are all
/// ASCII, and the table is easy to swap if that ever stops being true.
func postBytes(_ s: String) {
    let src = CGEventSource(stateID: .hidSystemState)
    for ch in s {
        var code: CGKeyCode; var shift = false; var ctrl = false
        if let hit = ASCII_KEYS[ch] {
            (code, shift) = hit
        } else if let v = ch.unicodeScalars.first?.value, (1...26).contains(v),
                  let letter = Unicode.Scalar(v + 96).map({ Character($0) }),
                  let hit = ASCII_KEYS[letter] {
            // Ctrl-Z etc: press the letter with Control held, as a person does.
            code = hit.0; ctrl = true
        } else { continue }
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        else { continue }
        var flags: CGEventFlags = []
        if shift { flags.insert(.maskShift) }
        if ctrl  { flags.insert(.maskControl) }
        down.flags = flags; up.flags = flags

        // Control needs to be genuinely HELD, not merely asserted in the
        // event's flags (2026-08-04: Ctrl-Z reached nothing until this).
        // Shift survives flags-only because the character is derived from
        // keycode+shift, but a client reading modifier STATE sees no Control
        // unless a flagsChanged event says so — which is what a real keyboard
        // sends. kVK_Control = 0x3B.
        func modifier(_ down: Bool) {
            guard ctrl, let e = CGEvent(keyboardEventSource: src,
                                        virtualKey: 0x3B, keyDown: down) else { return }
            e.type = .flagsChanged
            e.flags = down ? .maskControl : []
            e.post(tap: .cghidEventTap)
        }
        modifier(true)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        modifier(false)
    }
}

// MARK: - panel

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accept the click even though our window is not key — without this the first
/// click on an inactive window is swallowed to raise it.
class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Every cap is drawn by us, not by AppKit.
///
/// WHY: the .rounded bezel style draws a FIXED-HEIGHT bezel inside whatever
/// frame you give it, so a custom-coloured button (which fills its frame)
/// ends up visibly taller than its plain neighbours. Drawing them all the same
/// way is the only way to get a consistent keyboard.
final class FirstMousePopUp: NSPopUpButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class KeyButton: FirstMouseButton {
    var spec: KeySpec!
    private var normalBG: CGColor = NSColor.controlColor.cgColor

    /// `label` is passed explicitly rather than read from `title`: setting
    /// `attributedTitle` rewrites `title` to the whole two-line string, so a
    /// restyle (switching legend sets) would otherwise compound "F15\nHelp"
    /// into "F15\nHelp\nHelp".
    func style(label: String, gold: Bool, dark: Bool = false, conv: Bool = false,
               fontSize: CGFloat, legend: Legend?) {
        isBordered = false
        wantsLayer = true
        (cell as? NSButtonCell)?.wraps = true
        let goldColor = NSColor(calibratedRed: 0.831, green: 0.686, blue: 0.216, alpha: 1.0)
        let base = NSColor.controlColor.usingColorSpace(.sRGB) ?? NSColor.controlColor
        var plain = dark ? (base.blended(withFraction: 0.13, of: .black) ?? base) : base
        if conv { plain = base.blended(withFraction: 0.22, of: .systemTeal) ?? base }
        normalBG = (gold ? goldColor : plain).cgColor
        layer?.backgroundColor = normalBG
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 0
        let primary = gold ? NSColor.black : NSColor.labelColor

        let ms = NSMutableAttributedString(string: label, attributes: [
            .foregroundColor: primary,
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
            .paragraphStyle: para,
        ])
        // The secondary legend, exactly as it is silk-screened on the keycap.
        if let sub = legend?.legend, !sub.isEmpty {
            ms.append(NSAttributedString(string: "\n" + sub, attributes: [
                .foregroundColor: gold ? NSColor.black.withAlphaComponent(0.75)
                                       : NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 8, weight: .regular),
                .paragraphStyle: para,
            ]))
        }
        attributedTitle = ms

        // The Gold-shifted function is the red legend on a real cap, and the
        // unabbreviated wording has nowhere to go at this size — both live in
        // the tooltip.
        var tips: [String] = []
        if let n = legend?.note, !n.isEmpty {
            tips.append("\(label)  →  \(n)")
        } else if let sub = legend?.legend, !sub.isEmpty {
            tips.append("\(label)  →  \(sub)")
        }
        if let g = legend?.gold, !g.isEmpty {
            tips.append("Gold + \(label)  →  \(g)")
        }
        toolTip = tips.isEmpty ? nil : tips.joined(separator: "\n")
    }

    // A pressed cap should look pressed.
    override func mouseDown(with event: NSEvent) {
        layer?.opacity = 0.55
        super.mouseDown(with: event)
        layer?.opacity = 1.0
    }
}

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NonActivatingPanel!
    var keyButtons: [KeyButton] = []
    var legendSets: [String: [String: Legend]] = [:]

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon, no menu bar takeover

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)

        let (profile, from) = loadProfile()
        sendMode = (profile.mode == "keycode") ? .keycode : .bytes

        // Legends are per-application: KP4 is "Word" to WPS-PLUS and "ADVANCE"
        // to EDT. Pick the set named by legendSet; no legends is fine.
        let setName = profile.legendSet ?? ""
        let activeLegends: [String: Legend] = profile.legends?[setName] ?? [:]
        legendSets = profile.legends ?? [:]

        let pad = CGFloat(profile.gap ?? 6)
        let w   = CGFloat(profile.keyWidth ?? 46)
        let h   = CGFloat(profile.keyHeight ?? 32)
        let rows = Dictionary(grouping: profile.keys, by: { $0.row ?? 0 })
                    .sorted { $0.key < $1.key }
        let widest = rows.map { $0.value.reduce(0) { $0 + max(1, $1.span ?? 1) } }.max() ?? 1
        let width  = pad + (w + pad) * CGFloat(widest)
        let keysH  = CGFloat(rows.count) * (h + pad)
        let height = keysH + 68   // room for the picker + status

        panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = profile.title
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let content = panel.contentView!

        func rowBottom(_ ri: Int) -> CGFloat {
            height - 12 - CGFloat(ri + 1) * (h + pad) + pad
        }
        for (ri, row) in rows.enumerated() {
            var col = 0
            for k in row.value {
                let span  = max(1, k.span ?? 1)
                let rspan = max(1, k.rowspan ?? 1)
                if let c = k.col { col = c }
                let cw = w * CGFloat(span) + pad * CGFloat(span - 1)
                let ch = h * CGFloat(rspan) + pad * CGFloat(rspan - 1)
                // A tall cap hangs down into the rows below, so its bottom is
                // the bottom of the LAST row it covers.
                let y = rowBottom(ri + rspan - 1)
                let x = pad + (w + pad) * CGFloat(col)
                let b = KeyButton(frame: NSRect(x: x, y: y, width: cw, height: ch))
                col += span
                b.spec = k
                let leg = activeLegends[k.label] ?? (k.legend.map { Legend(legend: $0) })
                b.style(label: k.label, gold: leg?.goldCap == true, dark: k.dark == true,
                        conv: k.conv == true,
                        fontSize: k.label.count > 4 ? 9 : 11, legend: leg)
                keyButtons.append(b)
                b.target = self
                b.action = #selector(hit(_:))
                content.addSubview(b)
            }
        }

        // Which application's legends to show. Byte mode works against every
        // target we have tested — terminals and ezalb alike — so the old
        // send-mode checkbox that lived here has been removed as dead weight.
        let about = FirstMouseButton(frame: NSRect(x: width - pad - 26, y: 28,
                                                   width: 26, height: 22))
        about.bezelStyle = .rounded
        about.title = "?"
        about.font = NSFont.systemFont(ofSize: 11)
        about.toolTip = "About DECkeys"
        about.target = self
        about.action = #selector(showAbout(_:))
        content.addSubview(about)

        let picker = FirstMousePopUp(frame: NSRect(x: pad, y: 28,
                                                   width: width - pad * 3 - 26, height: 22))
        picker.addItems(withTitles: ["None"] + legendSets.keys.sorted())
        picker.selectItem(withTitle: legendSets[setName] != nil ? setName : "None")
        picker.font = NSFont.systemFont(ofSize: 10)
        picker.target = self
        picker.action = #selector(pickLegends(_:))
        picker.toolTip = "Which application's key legends to display"
        content.addSubview(picker)

        let status = NSTextField(labelWithString: "sends to the frontmost app"
            + (trusted ? "" : "  (AX check: not trusted)"))
        status.frame = NSRect(x: pad, y: 6, width: width - pad * 2, height: 14)
        status.font = NSFont.systemFont(ofSize: 10)
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        content.addSubview(status)

        // Fixed, findable spot. center() lands on whichever display is "main",
        // which is not necessarily the one you are looking at.
        if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.minX + 40, y: vf.maxY - height - 40))
        }
        panel.orderFrontRegardless()   // show without activating us

        FileHandle.standardError.write("""
        DECkeys: accessibility=\(trusted)
        DECkeys: profile=\(from)
        DECkeys: keys=\(profile.keys.count) rows=\(rows.count) mode=\(profile.mode ?? "bytes")
        DECkeys: panel.frame=\(panel.frame) screens=\(NSScreen.screens.count)
        DECkeys: bytes: \(profile.keys.compactMap { k -> String? in
            guard let b = k.bytes else { return nil }
            let hex = expand(b).unicodeScalars.map { String(format: "%02x", $0.value) }.joined(separator: " ")
            return "\(k.label)=[\(hex)]"
        }.joined(separator: "  "))

        """.data(using: .utf8)!)
    }

    @objc func hit(_ sender: KeyButton) {
        switch sendMode {
        case .keycode:
            if let c = sender.spec.keycode { postKeycode(CGKeyCode(c)) }
        case .bytes:
            if let b = sender.spec.bytes { postBytes(expand(b)) }
        }
    }

    @objc func showAbout(_ sender: NSButton) {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let a = NSAlert()
        a.messageText = "DECkeys " + v
        a.informativeText =
            "An on-screen DEC keypad that sends to the frontmost application: "
            + "PF1-PF4 (Gold), the LK201 numeric and editing keypads, and F6-F20.\n\n"
            + "Key legends are transcribed from DEC's own manuals and from the "
            + "applications' on-screen keypad diagrams \u{2014} EDT, EVE, VMS MAIL "
            + "and VAX Notes.\n\n"
            + "Companion to ezalb, Antoni Sawicki's VT420 emulator.\n\n"
            + "GPL-2.0. No warranty."
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "GitHub")
        // The panel never takes focus, so nothing has activated us; without
        // this the alert opens behind whatever you were actually using.
        NSApp.activate(ignoringOtherApps: true)
        let r = a.runModal()
        NSApp.setActivationPolicy(.accessory)
        if r == .alertSecondButtonReturn,
           let u = URL(string: "https://github.com/kleinmatic/DECkeys") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc func pickLegends(_ sender: NSPopUpButton) {
        let set = legendSets[sender.titleOfSelectedItem ?? ""] ?? [:]
        for b in keyButtons {
            let leg = set[b.spec.label] ?? (b.spec.legend.map { Legend(legend: $0) })
            b.style(label: b.spec.label, gold: leg?.goldCap == true, dark: b.spec.dark == true,
                    conv: b.spec.conv == true,
                    fontSize: b.spec.label.count > 4 ? 9 : 11, legend: leg)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
