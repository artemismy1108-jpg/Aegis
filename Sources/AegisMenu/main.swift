import AppKit
import Foundation

struct ProviderTileSpec {
    var id: String
    var title: String
    var ready: Bool
    var usage: String
    var detail: String
    var copyProvider: String?
    var copyAlias: String?
}

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
        return orderedProviders(statusMap: statusMap).map { provider in
            let state = statusMap[provider]?.ready == true ? "ON " : "OFF"
            let model = statusMap[provider]?.model ?? "-"
            let usageText = usageMap[provider] ?? "usage unavailable"
            return "\(state) \(provider): \(model) | \(usageText)"
        }.joined(separator: "\n")
    }

    private func providerGrid(status: String, usage: String) -> NSView {
        let statusMap = providerStatusMap(status)
        let usageMap = providerUsageMap(usage)
        let tiles = providerTiles(statusMap: statusMap, usageMap: usageMap)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        for rowTiles in stride(from: 0, to: tiles.count, by: 2).map({ Array(tiles[$0..<min($0 + 2, tiles.count)]) }) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 8
            for tile in rowTiles {
                row.addArrangedSubview(providerTile(tile))
            }
            stack.addArrangedSubview(row)
        }
        return stack
    }

    private func providerTiles(statusMap: [String: (ready: Bool, model: String)], usageMap: [String: String]) -> [ProviderTileSpec] {
        var tiles: [ProviderTileSpec] = []
        let localKeys = availableKeyRefs()
        let localOpenRouterAliases = Set(localKeys.filter { $0.provider == "openrouter" }.map(\.alias))

        for provider in orderedProviders(statusMap: statusMap) {
            let ready = statusMap[provider]?.ready == true
            let usageText = usageMap[provider] ?? "no usage"
            if provider == "openrouter" {
                tiles.append(contentsOf: openRouterTiles(usageText: usageText, ready: ready, localAliases: localOpenRouterAliases))
                continue
            }
            let title = provider == "openai" ? "OpenAI/Codex" : provider.capitalized
            tiles.append(ProviderTileSpec(
                id: provider,
                title: title,
                ready: ready,
                usage: compactUsage(usageText),
                detail: usageText,
                copyProvider: provider,
                copyAlias: "personal"
            ))
        }
        return tiles
    }

    private func openRouterTiles(usageText: String, ready: Bool, localAliases: Set<String>) -> [ProviderTileSpec] {
        let parts = usageText.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let balance = parts.first ?? usageText
        var tiles = [
            ProviderTileSpec(
                id: "openrouter-balance",
                title: "OR Balance",
                ready: ready,
                usage: compactUsage(balance),
                detail: usageText,
                copyProvider: nil,
                copyAlias: nil
            )
        ]

        for item in parts.dropFirst() {
            let split = item.split(separator: ":", maxSplits: 1).map(String.init)
            guard split.count == 2 else { continue }
            let alias = split[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = split[1].trimmingCharacters(in: .whitespacesAndNewlines)
            tiles.append(ProviderTileSpec(
                id: "openrouter-\(alias)",
                title: "OR / \(alias)",
                ready: localAliases.contains(alias),
                usage: compactOpenRouterKeyUsage(detail),
                detail: "\(alias): \(detail)",
                copyProvider: "openrouter",
                copyAlias: alias
            ))
        }

        if tiles.count == 1, !usageText.contains("missing") {
            for keyRef in availableKeyRefs().filter({ $0.provider == "openrouter" && $0.alias != "management" }) {
                tiles.append(ProviderTileSpec(
                    id: "openrouter-\(keyRef.alias)",
                    title: "OR / \(keyRef.alias)",
                    ready: true,
                    usage: "key saved",
                    detail: "Local key saved. Refresh usage after OpenRouter responds.",
                    copyProvider: "openrouter",
                    copyAlias: keyRef.alias
                ))
            }
        }
        return tiles
    }

    private func orderedProviders(statusMap: [String: (ready: Bool, model: String)]) -> [String] {
        let preferred = ["openrouter", "openai"]
        let trailing = ["gemini"]
        let suppressed = Set(["minimax", "kimi"])
        let dynamic = statusMap.keys.sorted().filter {
            !preferred.contains($0) && !trailing.contains($0) && !suppressed.contains($0)
        }
        return (preferred + dynamic + trailing).filter { statusMap[$0] != nil }
    }

    private func providerTile(_ spec: ProviderTileSpec) -> NSView {
        let tile = ProviderTileView(
            id: spec.id,
            tooltip: "\(spec.title)\n\(spec.detail)\nClick to copy API key",
            action: { [weak self] _ in
                self?.copyTileAPIKey(spec)
            }
        )
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 8
        tile.layer?.borderWidth = 1
        tile.layer?.borderColor = (spec.ready ? NSColor.systemGreen.withAlphaComponent(0.55) : NSColor.systemRed.withAlphaComponent(0.55)).cgColor
        tile.layer?.backgroundColor = tileColor(ready: spec.ready, usage: spec.usage).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(stack)

        stack.addArrangedSubview(label(spec.title, font: .systemFont(ofSize: 12, weight: .semibold)))
        stack.addArrangedSubview(label(spec.ready ? "ON" : "OFF", font: .systemFont(ofSize: 22, weight: .bold), color: spec.ready ? .systemGreen : .systemRed))
        stack.addArrangedSubview(label(spec.usage, font: .monospacedSystemFont(ofSize: 10, weight: .regular), color: .secondaryLabelColor))

        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 182),
            tile.heightAnchor.constraint(equalToConstant: 74),
            stack.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: tile.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: tile.bottomAnchor, constant: -8)
        ])

        return tile
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

    private func compactOpenRouterKeyUsage(_ text: String) -> String {
        if let range = text.range(of: #"month [$][0-9]+(\.[0-9]+)?"#, options: .regularExpression) {
            return String(text[range]).replacingOccurrences(of: "month ", with: "")
        }
        if let range = text.range(of: #"used [$][0-9]+(\.[0-9]+)?"#, options: .regularExpression) {
            return String(text[range]).replacingOccurrences(of: "used ", with: "")
        }
        if let range = text.range(of: #"today [$][0-9]+(\.[0-9]+)?"#, options: .regularExpression) {
            return String(text[range])
        }
        if text.contains("unavailable") { return "no usage" }
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
            ("Copy Key", { [weak self] in self?.copyAPIKey() }),
            ("Update Key", { [weak self] in self?.updateAPIKey() }),
            ("Delete Key", { [weak self] in self?.deleteAPIKey() }),
        ])
        let row2 = buttonRow([
            ("Refresh", { [weak self] in self?.onRefresh() }),
            ("Setup", { [weak self] in self?.setupAndRefresh() }),
            ("Add OR Key", { [weak self] in self?.addOpenRouterKey() })
        ])
        let row3 = buttonRow([
            ("OR Mgmt", { [weak self] in self?.addOpenRouterManagementKey() }),
            ("OR Keys", { [weak self] in self?.runSilent(["open", "openrouter", "keys"]) }),
            ("Add Provider", { [weak self] in self?.addProvider() })
        ])
        let row4 = buttonRow([
            ("OpenAI Bill", { [weak self] in self?.runSilent(["open", "openai", "billing"]) }),
            ("Gemini Keys", { [weak self] in self?.runSilent(["open", "gemini", "keys"]) }),
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
            ("gemini", "Gemini", ["open", "gemini", "keys"])
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

    private func addOpenRouterKey() {
        guard let alias = promptText(title: "Add OpenRouter Key", message: "Key alias, e.g. personal, work, cursor", placeholder: "personal") else { return }
        let normalized = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != "management" else {
            showOutput(title: "Add OpenRouter Key", output: "Use OR Mgmt for the Management API key.")
            return
        }
        guard !normalized.isEmpty else { return }
        guard let secret = promptForAPIKey(provider: ("openrouter", "OpenRouter \(normalized)", ["open", "openrouter", "keys"])) else { return }

        let output = runAegis(["key", "set", "openrouter", normalized], input: secret)
        showOutput(title: "Add OpenRouter Key", output: output.isEmpty ? "OpenRouter/\(normalized) stored." : output)
        onRefresh()
    }

    private func addOpenRouterManagementKey() {
        guard let secret = promptForAPIKey(provider: ("openrouter", "OpenRouter Management", ["open", "openrouter", "keys"])) else { return }
        let output = runAegis(["key", "set", "openrouter", "management"], input: secret)
        showOutput(title: "OpenRouter Management", output: output.isEmpty ? "OpenRouter/management stored." : output)
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
        guard let keyRef = chooseKey(title: "Copy API Key", actionTitle: "Copy", message: "Choose one key to copy directly to clipboard.") else { return }
        copyAPIKey(provider: keyRef.provider, alias: keyRef.alias)
    }

    private func copyAPIKey(provider: String) {
        let alias = provider == "openrouter" ? preferredOpenRouterAlias() : "personal"
        copyAPIKey(provider: provider, alias: alias)
    }

    private func copyAPIKey(provider: String, alias: String) {
        let key = runAegis(["key", "reveal", provider, alias])
        guard !key.isEmpty, !key.hasPrefix("aegis:") else {
            showOutput(title: "Copy API Key", output: key.isEmpty ? "No key found for \(provider)/\(alias)." : key)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        showOutput(title: "Copy API Key", output: "\(provider)/\(alias) API key copied to clipboard.")
    }

    private func copyTileAPIKey(_ spec: ProviderTileSpec) {
        guard let provider = spec.copyProvider, let alias = spec.copyAlias else {
            showOutput(title: "Copy API Key", output: "\(spec.title) is a usage card, not an API key.")
            return
        }
        copyAPIKey(provider: provider, alias: alias)
    }

    private func updateAPIKey() {
        guard let keyRef = chooseKey(title: "Update API Key", actionTitle: "Update", message: "Choose the key that should be replaced.") else { return }
        guard let secret = promptForAPIKey(provider: (keyRef.provider, keyRef.provider.capitalized, [])) else { return }
        let output = runAegis(["key", "set", keyRef.provider, keyRef.alias], input: secret)
        showOutput(title: "Update API Key", output: output.isEmpty ? "\(keyRef.provider)/\(keyRef.alias) key updated." : output)
        onRefresh()
    }

    private func deleteAPIKey() {
        guard let keyRef = chooseKey(title: "Delete API Key", actionTitle: "Delete", message: "Choose the provider key to delete from macOS Keychain.") else { return }
        let confirm = NSAlert()
        confirm.messageText = "Delete \(keyRef.provider)/\(keyRef.alias) API Key?"
        confirm.informativeText = "This removes the Keychain item aegis.\(keyRef.provider)/\(keyRef.alias)."
        confirm.addButton(withTitle: "Delete")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let output = runAegis(["key", "delete", keyRef.provider, keyRef.alias])
        showOutput(title: "Delete API Key", output: output.isEmpty ? "\(keyRef.provider)/\(keyRef.alias) key deleted." : output)
        onRefresh()
    }

    private func chooseKey(title: String, actionTitle: String, message: String) -> (provider: String, alias: String)? {
        let keyRefs = availableKeyRefs()
        guard !keyRefs.isEmpty else {
            showOutput(title: title, output: "No keys configured.")
            return nil
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        popup.addItems(withTitles: keyRefs.map { "\($0.provider)/\($0.alias)" })
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn,
              let selected = popup.selectedItem?.title
        else {
            return nil
        }
        let parts = selected.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private func availableKeyRefs() -> [(provider: String, alias: String)] {
        runAegis(["key", "list"])
            .split(separator: "\n")
            .map(String.init)
            .compactMap { line in
                let parts = line.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }
    }

    private func preferredOpenRouterAlias() -> String {
        availableKeyRefs().first { $0.provider == "openrouter" }?.alias ?? "personal"
    }

    private func chooseProvider(title: String, actionTitle: String, message: String) -> String? {
        let providers = providerStatusMap(runAegis(["status"])).keys.sorted()
        guard !providers.isEmpty else {
            showOutput(title: title, output: "No providers configured.")
            return nil
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        popup.addItems(withTitles: providers)
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return popup.selectedItem?.title
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

final class ProviderTileView: NSView {
    private let id: String
    private let action: (String) -> Void

    init(id: String, tooltip: String, action: @escaping (String) -> Void) {
        self.id = id
        self.action = action
        super.init(frame: .zero)
        self.toolTip = tooltip
        self.translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        action(id)
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
