import AppKit
import Foundation

final class AegisMenuApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var aegisPath: String {
        Bundle.main.path(forResource: "aegis", ofType: nil)
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent("aegis")
                .path
    }
    private var priceFixturePath: String? {
        Bundle.main.path(forResource: "openrouter-models.sample", ofType: "json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "Aegis"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showMenu)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func showMenu() {
        let menu = NSMenu()
        refreshStatusTitle()
        addHeader("Aegis", to: menu)
        menu.addItem(.separator())

        addOutputSection("Providers", ["status"], to: menu, maxLines: 6)
        menu.addItem(.separator())

        addOutputSection("OpenRouter Usage", ["usage", "openrouter"], to: menu, maxLines: 6)
        menu.addItem(.separator())

        var priceArgs = ["price-watch"]
        if let priceFixturePath = priceFixturePath {
            priceArgs.append(priceFixturePath)
        }
        addOutputSection("Price Watch", priceArgs, to: menu, maxLines: 5)
        menu.addItem(.separator())

        addOutputSection("Config Scan", ["scan"], to: menu, maxLines: 8)
        menu.addItem(.separator())

        addCommand("Refresh", ["status"], to: menu)
        addCommand("Doctor Details", ["doctor"], to: menu)
        addCommand("Scan Suggestions", ["scan", "--suggest"], to: menu)
        addOpenSubmenu(to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func addHeader(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addOutputSection(_ title: String, _ args: [String], to menu: NSMenu, maxLines: Int) {
        addHeader(title, to: menu)
        let output = runAegis(args)
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        let visible = lines.isEmpty ? ["No data"] : Array(lines.prefix(maxLines))
        for line in visible {
            let item = NSMenuItem(title: "  \(line)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if lines.count > maxLines {
            let item = NSMenuItem(title: "  ...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    private func addCommand(_ title: String, _ args: [String], to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(runCommand(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = args
        menu.addItem(item)
    }

    private func addOpenSubmenu(to menu: NSMenu) {
        let parent = NSMenuItem(title: "Open Provider Page", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for provider in ["openrouter", "openai", "gemini", "minimax"] {
            for target in ["dashboard", "billing", "keys"] {
                let item = NSMenuItem(
                    title: "\(provider) \(target)",
                    action: #selector(runCommand(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = ["open", provider, target]
                submenu.addItem(item)
            }
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let args = sender.representedObject as? [String] else { return }
        let output = runAegis(args)
        showOutput(title: sender.title, output: output)
    }

    private func runAegis(_ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: aegisPath)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Failed to run aegis: \(error.localizedDescription)"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func showOutput(title: String, output: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = output.isEmpty ? "Done" : output
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func refreshStatusTitle() {
        let output = runAegis(["status"])
        let ready = output
            .split(separator: "\n")
            .filter { $0.contains("ready") }
            .count
        statusItem.button?.title = ready > 0 ? "Aegis \(ready)/4" : "Aegis"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AegisMenuApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
