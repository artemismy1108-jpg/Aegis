import AppKit
import Foundation

final class AegisMenuApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var controller: AegisPanelController?

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
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: 460)
        replacePanelContent()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        replacePanelContent()
        refreshStatusTitle()
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func replacePanelContent() {
        let nextController = AegisPanelController(
            aegisPath: aegisPath,
            priceFixturePath: priceFixturePath,
            onRefresh: { [weak self] in
                DispatchQueue.main.async {
                    self?.replacePanelContent()
                    self?.refreshStatusTitle()
                }
            }
        )
        nextController.refresh()
        controller = nextController
        popover.contentViewController = nextController
    }

    private func refreshStatusTitle() {
        let ready = controller?.providerStatus
            .split(separator: "\n")
            .filter { $0.contains("ready") }
            .count ?? 0
        statusItem.button?.title = ready > 0 ? "Aegis \(ready)/4" : "Aegis"
    }
}

final class AegisPanelController: NSViewController {
    private let aegisPath: String
    private let priceFixturePath: String?
    private let onRefresh: () -> Void
    private let root = NSStackView()
    private let scrollView = NSScrollView()

    private(set) var providerStatus = ""

    init(aegisPath: String, priceFixturePath: String?, onRefresh: @escaping () -> Void) {
        self.aegisPath = aegisPath
        self.priceFixturePath = priceFixturePath
        self.onRefresh = onRefresh
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 460))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: document.topAnchor, constant: 14),
            root.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -14)
        ])
    }

    func refresh() {
        clearRoot()

        ensureConfig()
        providerStatus = runAegis(["status"])
        let usage = runAegis(["usage"])
        var priceArgs = ["price-watch"]
        if let priceFixturePath = priceFixturePath {
            priceArgs.append(priceFixturePath)
        }
        let prices = runAegis(priceArgs)

        root.addArrangedSubview(titleBlock())
        root.addArrangedSubview(providerGrid(status: providerStatus, usage: usage))
        root.addArrangedSubview(section(title: "Price Watch", body: prices, maxLines: 3))
        root.addArrangedSubview(section(title: "Connect Keys", body: connectKeysSummary(), maxLines: 2))
        root.addArrangedSubview(section(title: "Providers", body: providerStatus, maxLines: 3))
        root.addArrangedSubview(actionsGrid())
        view.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func clearRoot() {
        for view in root.arrangedSubviews {
            root.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func ensureConfig() {
        let status = runAegis(["status"])
        if status.contains("missing config") {
            _ = runAegis(["setup"])
        }
    }

    private func titleBlock() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3

        let title = label("Aegis", font: .systemFont(ofSize: 20, weight: .semibold))
        let subtitle = label("LLM keys, spend, routes, and config", color: .secondaryLabelColor)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        return stack
    }

    private func connectKeysSummary() -> String {
        """
        Setup stores keys in macOS Keychain.
        Copy Key copies the selected key to clipboard.
        """
    }

    private func modelStatusSummary(status: String, usage: String) -> String {
        let statusMap = providerStatusMap(status)
        let usageMap = providerUsageMap(usage)
        return ["openai", "gemini", "openrouter", "minimax"].map { provider in
            let state = statusMap[provider]?.ready == true ? "ON " : "OFF"
            let model = statusMap[provider]?.model ?? "-"
            let usageText = usageMap[provider] ?? "usage unavailable"
            return "\(state) \(provider): \(model) | \(usageText)"
        }.joined(separator: "\n")
    }

    private func providerGrid(status: String, usage: String) -> NSView {
        let statusMap = providerStatusMap(status)
        let usageMap = providerUsageMap(usage)
        let preferred = ["openai", "gemini", "openrouter", "minimax"]
        let dynamic = statusMap.keys.sorted()
        let providers = (preferred + dynamic).reduce(into: [String]()) { result, provider in
            if !result.contains(provider), statusMap[provider] != nil {
                result.append(provider)
            }
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        for rowProviders in stride(from: 0, to: providers.count, by: 2).map({ Array(providers[$0..<min($0 + 2, providers.count)]) }) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 8
            for provider in rowProviders {
                let ready = statusMap[provider]?.ready == true
                let usageText = usageMap[provider] ?? "no usage"
                row.addArrangedSubview(providerTile(provider: provider, ready: ready, usage: compactUsage(usageText)))
            }
            stack.addArrangedSubview(row)
        }
        return stack
    }

    private func providerTile(provider: String, ready: Bool, usage: String) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = ready ? NSColor.systemGreen.withAlphaComponent(0.55) : NSColor.systemRed.withAlphaComponent(0.55)
        box.fillColor = tileColor(ready: ready, usage: usage)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)

        let name = provider == "openai" ? "OpenAI/Codex" : provider.capitalized
        stack.addArrangedSubview(label(name, font: .systemFont(ofSize: 12, weight: .semibold)))
        stack.addArrangedSubview(label(ready ? "ON" : "OFF", font: .systemFont(ofSize: 22, weight: .bold), color: ready ? .systemGreen : .systemRed))
        stack.addArrangedSubview(label(usage, font: .monospacedSystemFont(ofSize: 10, weight: .regular), color: .secondaryLabelColor))

        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 182),
            box.heightAnchor.constraint(equalToConstant: 74),
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: box.contentView!.bottomAnchor, constant: -8)
        ])

        return box
    }

    private func compactUsage(_ text: String) -> String {
        if text.contains("missing") || text.contains("unavailable") { return "no usage" }
        if let range = text.range(of: #"[$][0-9]+(\.[0-9]+)?"#, options: .regularExpression) {
            return String(text[range])
        }
        if let range = text.range(of: #"[0-9]+(\.[0-9]+)?% remaining"#, options: .regularExpression) {
            return String(text[range])
        }
        if text.contains("key ready") { return "key ready" }
        return String(text.prefix(20))
    }

    private func tileColor(ready: Bool, usage: String) -> NSColor {
        guard ready else { return NSColor.systemRed.withAlphaComponent(0.10) }
        if usage.contains("manual") || usage.contains("key ready") {
            return NSColor.systemBlue.withAlphaComponent(0.10)
        }
        if let value = Double(usage.split(separator: "%").first ?? ""), value < 30 {
            return NSColor.systemYellow.withAlphaComponent(0.16)
        }
        return NSColor.systemGreen.withAlphaComponent(0.10)
    }

    private func providerStatusMap(_ status: String) -> [String: (ready: Bool, model: String)] {
        var result: [String: (ready: Bool, model: String)] = [:]
        for line in status.split(separator: "\n").map(String.init) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let provider = parts[0]
            let body = parts[1]
            let ready = body.contains("ready")
            let model = extractBetween(body, start: "model ", end: ",") ?? "-"
            result[provider] = (ready, model)
        }
        return result
    }

    private func providerUsageMap(_ usage: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in usage.split(separator: "\n").map(String.init) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            result[parts[0]] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private func extractBetween(_ text: String, start: String, end: String) -> String? {
        guard let startRange = text.range(of: start) else { return nil }
        let rest = text[startRange.upperBound...]
        if let endRange = rest.range(of: end) {
            return String(rest[..<endRange.lowerBound])
        }
        return String(rest)
    }

    private func section(title: String, body: String, maxLines: Int) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = NSColor.separatorColor
        box.fillColor = NSColor.controlBackgroundColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)

        stack.addArrangedSubview(label(title, font: .systemFont(ofSize: 13, weight: .semibold)))

        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        let visible = lines.isEmpty ? ["No data"] : Array(lines.prefix(maxLines))
        for line in visible {
            stack.addArrangedSubview(label(line, font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: color(for: line)))
        }
        if lines.count > maxLines {
            stack.addArrangedSubview(label("...", font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor))
        }

        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 372),
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor, constant: -9)
        ])

        return box
    }

    private func actionsGrid() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let row1 = buttonRow([
            ("Refresh", { [weak self] in self?.onRefresh() }),
            ("Setup", { [weak self] in self?.setupAndRefresh() }),
            ("Copy Key", { [weak self] in self?.copyAPIKey() }),
        ])
        let row2 = buttonRow([
            ("Doctor", { [weak self] in self?.showCommand("Doctor", ["doctor"]) }),
            ("Add Provider", { [weak self] in self?.addProvider() }),
            ("Copy Codex", { [weak self] in self?.copyCommand(["export", "codex"]) })
        ])
        let row3 = buttonRow([
            ("OR Keys", { [weak self] in self?.runSilent(["open", "openrouter", "keys"]) }),
            ("OpenAI Bill", { [weak self] in self?.runSilent(["open", "openai", "billing"]) }),
            ("Gemini Keys", { [weak self] in self?.runSilent(["open", "gemini", "keys"]) })
        ])
        let row4 = buttonRow([
            ("MiniMax", { [weak self] in self?.runSilent(["open", "minimax", "dashboard"]) }),
            ("Quit", { NSApp.terminate(nil) })
        ])

        stack.addArrangedSubview(row1)
        stack.addArrangedSubview(row2)
        stack.addArrangedSubview(row3)
        stack.addArrangedSubview(row4)
        return stack
    }

    private func buttonRow(_ specs: [(String, () -> Void)]) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        for spec in specs {
            let button = ClosureButton(title: spec.0, action: spec.1)
            button.bezelStyle = .rounded
            button.widthAnchor.constraint(equalToConstant: 118).isActive = true
            row.addArrangedSubview(button)
        }
        return row
    }

    private func showCommand(_ title: String, _ args: [String]) {
        showOutput(title: title, output: runAegis(args))
    }

    private func setupAndRefresh() {
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
        onRefresh()
    }

    private func setupProviders() -> [(name: String, displayName: String, keyURLArg: [String])] {
        [
            ("openrouter", "OpenRouter", ["open", "openrouter", "keys"]),
            ("openai", "OpenAI", ["open", "openai", "keys"]),
            ("gemini", "Gemini", ["open", "gemini", "keys"]),
            ("minimax", "MiniMax", ["open", "minimax", "dashboard"])
        ]
    }

    private func addProvider() {
        guard let name = promptText(title: "Add Provider", message: "Provider name, e.g. kimi", placeholder: "kimi") else { return }
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let defaultEnv = "\(normalized.uppercased())_API_KEY"
        guard let env = promptText(title: "Add Provider", message: "API key environment variable, not the key itself", placeholder: defaultEnv) else { return }
        if env.contains("sk-") || env.count > 80 || env.contains("-") {
            showOutput(title: "Add Provider", output: "That looks like an API key. Use an env name like \(defaultEnv), then paste the actual key in the next secure prompt.")
            return
        }
        guard let baseURL = promptText(title: "Add Provider", message: "Base URL", placeholder: "https://api.moonshot.cn/v1") else { return }
        guard let model = promptText(title: "Add Provider", message: "Default model", placeholder: "kimi-k2") else { return }

        let output = runAegis(["provider", "add", normalized, env, baseURL, model])
        if output.hasPrefix("aegis:") {
            showOutput(title: "Add Provider", output: output)
            return
        }

        if let secret = promptForAPIKey(provider: (normalized, normalized.capitalized, [])) {
            _ = runAegis(["key", "set", normalized, "personal"], input: secret)
        }
        showOutput(title: "Add Provider", output: output.isEmpty ? "Provider added." : output)
        onRefresh()
    }

    private func promptText(title: String, message: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = placeholder
        input.stringValue = placeholder
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
                if !provider.keyURLArg.isEmpty {
                    runSilent(provider.keyURLArg)
                }
            } else {
                return nil
            }
        }
    }

    private func copyBindKeyCommands() {
        let commands = """
        printf '%s' "$OPENAI_API_KEY" | aegis key set openai personal
        printf '%s' "$GEMINI_API_KEY" | aegis key set gemini personal
        printf '%s' "$OPENROUTER_API_KEY" | aegis key set openrouter personal
        printf '%s' "$MINIMAX_API_KEY" | aegis key set minimax personal
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands, forType: .string)
        showOutput(title: "Bind Keys", output: "Copied Keychain setup commands to clipboard. Paste them in Terminal after exporting each provider API key.")
    }

    private func copyAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Copy API Key"
        alert.informativeText = "Choose one key to copy directly to clipboard."
        alert.addButton(withTitle: "OpenAI")
        alert.addButton(withTitle: "Gemini")
        alert.addButton(withTitle: "OpenRouter")
        alert.addButton(withTitle: "MiniMax")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        let provider: String
        switch response {
        case .alertFirstButtonReturn:
            provider = "openai"
        case .alertSecondButtonReturn:
            provider = "gemini"
        case .alertThirdButtonReturn:
            provider = "openrouter"
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1):
            provider = "minimax"
        default:
            return
        }

        let key = runAegis(["key", "reveal", provider, "personal"])
        guard !key.isEmpty, !key.hasPrefix("aegis:") else {
            showOutput(title: "Copy API Key", output: key.isEmpty ? "No key found for \(provider)." : key)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        showOutput(title: "Copy API Key", output: "\(provider) API key copied to clipboard.")
    }

    private func runSilent(_ args: [String]) {
        _ = runAegis(args)
    }

    private func copyCommand(_ args: [String]) {
        let output = runAegis(args)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        showOutput(title: "Copied", output: output.isEmpty ? "No output" : "Copied to clipboard.")
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

    private func label(_ text: String, font: NSFont = .systemFont(ofSize: 12), color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        return field
    }

    private func color(for line: String) -> NSColor {
        if line.contains("ready") || line.contains("saves") { return .systemGreen }
        if line.contains("missing") || line.contains("HTTP") || line.contains("aegis:") { return .systemRed }
        return .labelColor
    }
}

final class ClosureButton: NSButton {
    private let closure: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.closure = action
        super.init(frame: .zero)
        self.title = title
        self.target = self
        self.action = #selector(run)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func run() {
        closure()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

let app = NSApplication.shared
let delegate = AegisMenuApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
