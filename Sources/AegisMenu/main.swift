import AppKit
import Foundation

final class AegisMenuApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var providerStatus = ""
    private var openRouterUsage = ""
    private var priceWatch = ""

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
        statusItem.menu = menu
        refreshData()
        rebuildMenu()
    }

    private func refreshData() {
        ensureConfig()
        providerStatus = runAegis(["status"])
        openRouterUsage = runAegis(["usage", "openrouter"])
        var priceArgs = ["price-watch"]
        if let priceFixturePath = priceFixturePath {
            priceArgs.append(priceFixturePath)
        }
        priceWatch = runAegis(priceArgs)
        refreshStatusTitle()
    }

    private func refreshStatusTitle() {
        let ready = providerStatus
            .split(separator: "\n")
            .filter { $0.contains("ready") }
            .count
        statusItem.button?.title = ready > 0 ? "Aegis \(ready)/4" : "Aegis"
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        addDisabled("Aegis")
        addDisabled("LLM keys, spend, routes, and config")
        menu.addItem(.separator())

        addDisabled("Connect Keys")
        addDisabled("Use Setup to store API keys in macOS Keychain.")
        addDisabled("OpenRouter balance works after adding its key.")
        menu.addItem(.separator())

        addSection(title: "Providers", body: providerStatus, limit: 6)
        addSection(title: "OpenRouter", body: openRouterUsage, limit: 4)
        addSection(title: "Price Watch", body: priceWatch, limit: 4)
        menu.addItem(.separator())

        addAction("Setup / Add API Keys", #selector(setupAction))
        addAction("Refresh", #selector(refreshAction))
        addAction("Doctor", #selector(doctorAction))
        addAction("Scan Config", #selector(scanAction))
        menu.addItem(.separator())

        addAction("Copy Codex Config", #selector(copyCodexAction))
        addAction("Copy Bind Commands", #selector(copyBindCommandsAction))
        menu.addItem(.separator())

        addAction("OpenRouter Keys", #selector(openRouterKeysAction))
        addAction("OpenAI Billing", #selector(openAIBillingAction))
        addAction("Gemini Keys", #selector(geminiKeysAction))
        addAction("MiniMax Dashboard", #selector(minimaxAction))
        menu.addItem(.separator())

        addAction("Quit Aegis", #selector(quitAction))
    }

    private func addSection(title: String, body: String, limit: Int) {
        addDisabled(title)
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        for line in Array(lines.prefix(limit)) {
            addDisabled("  \(line)")
        }
        if lines.count > limit {
            addDisabled("  ...")
        }
        menu.addItem(.separator())
    }

    private func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addAction(_ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func ensureConfig() {
        let status = runAegis(["status"])
        if status.contains("missing config") {
            _ = runAegis(["setup"])
        }
    }

    @objc private func setupAction() {
        let setupOutput = runAegis(["setup"])
        var stored: [String] = []
        var errors: [String] = []

        for provider in setupProviders() {
            guard let secret = promptForAPIKey(provider: provider) else {
                continue
            }
            let output = runAegis(["key", "set", provider.name, "personal"], input: secret)
            if output.contains("stored") {
                stored.append(provider.displayName)
            } else {
                errors.append("\(provider.displayName): \(output)")
            }
        }

        var summary = setupOutput
        if !stored.isEmpty {
            summary += "\n\nStored keys: \(stored.joined(separator: ", "))"
        }
        if !errors.isEmpty {
            summary += "\n\nErrors:\n\(errors.joined(separator: "\n"))"
        }
        if stored.isEmpty && errors.isEmpty {
            summary += "\n\nNo keys were added. You can run Setup again later."
        }
        showOutput(title: "Setup Complete", output: summary)
        refreshAction()
    }

    @objc private func refreshAction() {
        refreshData()
        rebuildMenu()
    }

    @objc private func doctorAction() {
        showOutput(title: "Doctor", output: runAegis(["doctor"]))
    }

    @objc private func scanAction() {
        showOutput(title: "Scan Config", output: runAegis(["scan", "--suggest"]))
    }

    @objc private func copyCodexAction() {
        copyOutput(title: "Copy Codex Config", args: ["export", "codex"])
    }

    @objc private func copyBindCommandsAction() {
        let commands = """
        printf '%s' "$OPENAI_API_KEY" | aegis key set openai personal
        printf '%s' "$GEMINI_API_KEY" | aegis key set gemini personal
        printf '%s' "$OPENROUTER_API_KEY" | aegis key set openrouter personal
        printf '%s' "$MINIMAX_API_KEY" | aegis key set minimax personal
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands, forType: .string)
        showOutput(title: "Copy Bind Commands", output: "Copied Keychain setup commands to clipboard.")
    }

    @objc private func openRouterKeysAction() {
        _ = runAegis(["open", "openrouter", "keys"])
    }

    @objc private func openAIBillingAction() {
        _ = runAegis(["open", "openai", "billing"])
    }

    @objc private func geminiKeysAction() {
        _ = runAegis(["open", "gemini", "keys"])
    }

    @objc private func minimaxAction() {
        _ = runAegis(["open", "minimax", "dashboard"])
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    private func setupProviders() -> [(name: String, displayName: String, keyURLArg: [String])] {
        [
            ("openrouter", "OpenRouter", ["open", "openrouter", "keys"]),
            ("openai", "OpenAI", ["open", "openai", "keys"]),
            ("gemini", "Gemini", ["open", "gemini", "keys"]),
            ("minimax", "MiniMax", ["open", "minimax", "dashboard"])
        ]
    }

    private func promptForAPIKey(provider: (name: String, displayName: String, keyURLArg: [String])) -> String? {
        let alert = NSAlert()
        alert.messageText = "Add \(provider.displayName) API Key"
        alert.informativeText = "Paste the API key to store it in macOS Keychain. Choose Open Keys to get one, or Skip to add it later."
        alert.addButton(withTitle: "Store")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Open Keys")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "\(provider.displayName) API key"
        alert.accessoryView = input

        while true {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let secret = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !secret.isEmpty {
                    return secret
                }
                NSSound.beep()
            } else if response == .alertThirdButtonReturn {
                _ = runAegis(provider.keyURLArg)
            } else {
                return nil
            }
        }
    }

    private func copyOutput(title: String, args: [String]) {
        let output = runAegis(args)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        showOutput(title: title, output: output.isEmpty ? "No output" : "Copied to clipboard.")
    }

    private func runAegis(_ args: [String], input: String? = nil) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: aegisPath)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let inputPipe = input.map { _ in Pipe() }
        if let inputPipe = inputPipe {
            process.standardInput = inputPipe
        }

        do {
            try process.run()
            if let input = input, let inputPipe = inputPipe {
                inputPipe.fileHandleForWriting.write(Data(input.utf8))
                inputPipe.fileHandleForWriting.closeFile()
            }
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
}

let app = NSApplication.shared
let delegate = AegisMenuApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
