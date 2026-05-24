import AppKit
import Foundation

// MARK: - Model Pricing (USD per million tokens)

struct Pricing {
    let input: Double
    let output: Double
    let cacheCreate: Double
    let cacheRead: Double
}

let modelPricing: [String: Pricing] = [
    "claude-opus-4-7":           Pricing(input: 15.00, output: 75.00, cacheCreate: 18.75, cacheRead: 1.50),
    "claude-opus-4-6":           Pricing(input: 15.00, output: 75.00, cacheCreate: 18.75, cacheRead: 1.50),
    "claude-sonnet-4-6":         Pricing(input:  3.00, output: 15.00, cacheCreate:  3.75, cacheRead: 0.30),
    "claude-sonnet-4-5":         Pricing(input:  3.00, output: 15.00, cacheCreate:  3.75, cacheRead: 0.30),
    "claude-haiku-4-5":          Pricing(input:  0.80, output:  4.00, cacheCreate:  1.00, cacheRead: 0.08),
    "claude-haiku-4-5-20251001": Pricing(input:  0.80, output:  4.00, cacheCreate:  1.00, cacheRead: 0.08),
]

let fallbackPricing = Pricing(input: 3.00, output: 15.00, cacheCreate: 3.75, cacheRead: 0.30)

func messageCost(usage: [String: Any], model: String) -> Double {
    let p = modelPricing[model] ?? fallbackPricing
    let inp = Double(usage["input_tokens"]               as? Int ?? 0)
    let out = Double(usage["output_tokens"]              as? Int ?? 0)
    let cc  = Double(usage["cache_creation_input_tokens"] as? Int ?? 0)
    let cr  = Double(usage["cache_read_input_tokens"]     as? Int ?? 0)
    return (inp * p.input + out * p.output + cc * p.cacheCreate + cr * p.cacheRead) / 1_000_000
}

// MARK: - Config

struct Config: Codable {
    var fiveHourLimit: Double
    var sevenDayLimit: Double

    static let configPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".config/burnrate/config.json")

    static func load() -> Config {
        if let data = FileManager.default.contents(atPath: configPath),
           let cfg  = try? JSONDecoder().decode(Config.self, from: data) { return cfg }
        return Config(fiveHourLimit: 7.0, sevenDayLimit: 40.0)
    }
}

// MARK: - Data Source

struct LiveData {
    var fiveHourPct: Double   // 0–100, from Claude Code hook
    var sevenDayPct: Double
}

struct ComputedData {
    var fiveHourCost: Double  // USD, from JSONL calculation
    var sevenDayCost: Double
}

/// Try reading from ~/.burnrate-data.json (written by burnrate-hook.sh).
/// Returns nil if file is absent or stale (> 10 min).
func readLiveData() -> LiveData? {
    let path = (NSHomeDirectory() as NSString).appendingPathComponent(".burnrate-data.json")
    guard
        let raw  = FileManager.default.contents(atPath: path),
        let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
        let fh   = json["five_hour_pct"] as? Double,
        let sd   = json["seven_day_pct"] as? Double,
        fh >= 0, sd >= 0,
        let ts   = json["updated_at"] as? Double,
        Date().timeIntervalSince1970 - ts < 600          // stale after 10 min
    else { return nil }
    return LiveData(fiveHourPct: fh, sevenDayPct: sd)
}

// MARK: - JSONL Fallback

private let isoFull: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoBasic: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseISO(_ s: String) -> Date? { isoFull.date(from: s) ?? isoBasic.date(from: s) }

func computeFromJSONL() -> ComputedData {
    let now          = Date()
    let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
    let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)

    var fhCost = 0.0, sdCost = 0.0
    var seenIds = Set<String>()

    let projectsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
    let fm = FileManager.default
    guard let projects = try? fm.contentsOfDirectory(atPath: projectsDir) else {
        return ComputedData(fiveHourCost: 0, sevenDayCost: 0)
    }

    for project in projects {
        let projPath = (projectsDir as NSString).appendingPathComponent(project)
        guard let files = try? fm.contentsOfDirectory(atPath: projPath) else { continue }

        for file in files where file.hasSuffix(".jsonl") {
            let fp = (projPath as NSString).appendingPathComponent(file)
            guard let content = try? String(contentsOfFile: fp, encoding: .utf8) else { continue }

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard
                    let data = line.data(using: .utf8),
                    let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let tsStr   = obj["timestamp"] as? String,
                    let ts      = parseISO(tsStr),
                    ts > sevenDaysAgo,
                    let message = obj["message"] as? [String: Any],
                    let usage   = message["usage"] as? [String: Any],
                    let model   = message["model"] as? String,
                    let msgId   = message["id"] as? String,
                    seenIds.insert(msgId).inserted
                else { continue }

                let cost = messageCost(usage: usage, model: model)
                sdCost += cost
                if ts >= fiveHoursAgo { fhCost += cost }
            }
        }
    }

    return ComputedData(fiveHourCost: fhCost, sevenDayCost: sdCost)
}

// MARK: - Combined result for display

struct DisplayValues {
    var fiveHourFraction: Double
    var sevenDayFraction: Double
    var fiveHourLabel: String
    var sevenDayLabel: String
    var isLive: Bool      // true = from hook, false = computed
}

func buildDisplay() -> DisplayValues {
    if let live = readLiveData() {
        return DisplayValues(
            fiveHourFraction: live.fiveHourPct / 100,
            sevenDayFraction: live.sevenDayPct / 100,
            fiveHourLabel: "\(Int(live.fiveHourPct))%",
            sevenDayLabel:  "\(Int(live.sevenDayPct))%",
            isLive: true
        )
    }
    let cfg  = Config.load()
    let data = computeFromJSONL()
    let fhF  = cfg.fiveHourLimit > 0 ? data.fiveHourCost / cfg.fiveHourLimit : 0
    let sdF  = cfg.sevenDayLimit > 0 ? data.sevenDayCost / cfg.sevenDayLimit : 0
    return DisplayValues(
        fiveHourFraction: fhF,
        sevenDayFraction: sdF,
        fiveHourLabel: "\(Int(fhF * 100))%",
        sevenDayLabel:  "\(Int(sdF * 100))%",
        isLive: false
    )
}

// MARK: - Drawing

func arcColor(fraction: Double) -> NSColor {
    if fraction < 0.6 { return NSColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1) }
    if fraction < 0.8 { return NSColor(red: 1.000, green: 0.584, blue: 0.000, alpha: 1) }
    return             NSColor(red: 1.000, green: 0.231, blue: 0.188, alpha: 1)
}

func makeStatusImage(fiveHour: Double, sevenDay: Double) -> NSImage {
    let dial: CGFloat = 18
    let gap:  CGFloat = 5
    let h:    CGFloat = 22
    let w             = dial * 2 + gap

    let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
        func draw(originX: CGFloat, fraction: Double) {
            let center = CGPoint(x: originX + dial / 2, y: h / 2)
            let radius = dial / 2 - 1.5
            let lw: CGFloat = 2.0

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            NSColor(white: 0.5, alpha: 0.22).setStroke()
            track.lineWidth = lw
            track.stroke()

            let clamped = min(max(fraction, 0), 1)
            guard clamped > 0.005 else { return }

            arcColor(fraction: fraction).setStroke()

            if clamped >= 0.999 {
                let full = NSBezierPath()
                full.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                full.lineWidth = lw
                full.stroke()
            } else {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius,
                              startAngle: 90, endAngle: 90 - clamped * 360, clockwise: true)
                arc.lineWidth = lw
                arc.lineCapStyle = .round
                arc.stroke()
            }
        }

        draw(originX: 0,         fraction: fiveHour)
        draw(originX: dial + gap, fraction: sevenDay)
        return true
    }
    img.isTemplate = false
    return img
}

// MARK: - Status Bar Controller

class StatusBarController {
    private var item:        NSStatusItem!
    private var timer:       Timer?
    private var fiveHourItem: NSMenuItem!
    private var sevenDayItem: NSMenuItem!
    private var sourceItem:   NSMenuItem!

    func setup() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = makeStatusImage(fiveHour: 0, sevenDay: 0)

        let menu = NSMenu()

        fiveHourItem  = NSMenuItem(title: "5h:  —", action: nil, keyEquivalent: "")
        sevenDayItem  = NSMenuItem(title: "7d:  —", action: nil, keyEquivalent: "")
        sourceItem    = NSMenuItem(title: "", action: nil, keyEquivalent: "")

        fiveHourItem.isEnabled  = false
        sevenDayItem.isEnabled  = false
        sourceItem.isEnabled    = false

        menu.addItem(fiveHourItem)
        menu.addItem(sevenDayItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(sourceItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit BurnRate",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        item.menu = menu

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let display = buildDisplay()
            DispatchQueue.main.async {
                self?.apply(display)
            }
        }
    }

    private func apply(_ d: DisplayValues) {
        item.button?.image    = makeStatusImage(fiveHour: d.fiveHourFraction, sevenDay: d.sevenDayFraction)
        item.button?.toolTip  = "5h: \(d.fiveHourLabel)  |  7d: \(d.sevenDayLabel)"
        fiveHourItem.title    = "5h:   \(d.fiveHourLabel)"
        sevenDayItem.title    = "7d:   \(d.sevenDayLabel)"
        sourceItem.title      = d.isLive ? "● live" : "○ estimated"
    }
}

// MARK: - Auto Setup

// Standalone hook installed when no statusLine exists
private let standaloneHook = #"""
#!/bin/bash
# BurnRate hook for Claude Code statusLine
input=$(cat)
FH=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SD=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$FH" ] && [ -n "$SD" ]; then
    printf '{"five_hour_pct":%s,"seven_day_pct":%s,"updated_at":%s}\n' \
        "$FH" "$SD" "$(date +%s)" > ~/.burnrate-data.json
fi
"""#

// Block appended to existing statusLine scripts (uses $input if present)
private let appendBlock = #"""


# BurnRate-v1
_br_fh=$(echo "${input:-}" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
_br_sd=$(echo "${input:-}" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
if [ -n "$_br_fh" ] && [ -n "$_br_sd" ]; then
    printf '{"five_hour_pct":%s,"seven_day_pct":%s,"updated_at":%s}\n' \
        "$_br_fh" "$_br_sd" "$(date +%s)" > ~/.burnrate-data.json
fi
"""#

func performSetup() {
    let fm          = FileManager.default
    let home        = NSHomeDirectory()
    let settingsPath = (home as NSString).appendingPathComponent(".claude/settings.json")
    let hookDir      = (home as NSString).appendingPathComponent(".config/burnrate")
    let hookPath     = (hookDir as NSString).appendingPathComponent("hook.sh")

    guard
        let data     = fm.contents(atPath: settingsPath),
        var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        // No settings.json — install hook script only (can't wire statusLine)
        writeHookScript(dir: hookDir, path: hookPath)
        return
    }

    if let sl   = settings["statusLine"] as? [String: Any],
       (sl["type"] as? String) == "command",
       let cmd  = sl["command"] as? String {

        let scriptPath = (cmd as NSString).expandingTildeInPath

        // Already pointing at our hook — nothing to do
        guard !scriptPath.contains("burnrate") else { return }

        // Append BurnRate block to existing script if not already there
        guard var content = try? String(contentsOfFile: scriptPath, encoding: .utf8),
              !content.contains("BurnRate-v1"),
              !content.contains("burnrate-data.json")
        else { return }

        content += appendBlock
        try? content.write(toFile: scriptPath, atomically: true, encoding: .utf8)

    } else if settings["statusLine"] == nil {
        // No statusLine at all — install ours
        writeHookScript(dir: hookDir, path: hookPath)
        settings["statusLine"] = ["type": "command", "command": "~/.config/burnrate/hook.sh"]
        if let out = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) {
            try? out.write(to: URL(fileURLWithPath: settingsPath))
        }
    }
    // else: statusLine exists but isn't a command — leave it alone
}

private func writeHookScript(dir: String, path: String) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? standaloneHook.write(toFile: path, atomically: true, encoding: .utf8)
    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
}

// MARK: - Entry Point

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusBarController?
    func applicationDidFinishLaunching(_: Notification) {
        DispatchQueue.global(qos: .background).async { performSetup() }
        controller = StatusBarController()
        controller?.setup()
    }
}

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
