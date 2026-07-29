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
        let usage = runAegis(["usage", "openrouter"])
        var priceArgs = ["price-watch"]
        if let priceFixturePath = priceFixturePath {
            priceArgs.append(priceFixturePath)
        }
        let prices = runAegis(priceArgs)
        let scan = runAegis(["scan"])

        root.addArrangedSubview(titleBlock())
        root.addArrangedSubview(section(title: "Connect Keys", body: connectKeysSummary(), maxLines: 3))
        root.addArrangedSubview(section(title: "Providers", body: providerStatus, maxLines: 4))
        root.addArrangedSubview(section(title: "OpenRouter", body: usage, maxLines: 3))
        root.addArrangedSubview(section(title: "Price Watch", body: prices, maxLines: 3))
        root.addArrangedSubview(section(title: "Config Scan", body: scan, maxLines: 3))
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
        Bind by storing API keys in macOS Keychain.
        OpenRouter balance works after OPENROUTER_API_KEY.
        OpenAI/Gemini/MiniMax currently link to billing pages.
        Use Bind Keys to copy setup commands.
        """
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
            ("Bind Keys", { [weak self] in self?.copyBindKeyCommands() }),
        ])
        let row2 = buttonRow([
            ("Doctor", { [weak self] in self?.showCommand("Doctor", ["doctor"]) }),
            ("Scan", { [weak self] in self?.showCommand("Scan Suggestions", ["scan", "--suggest"]) }),
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
                runSilent(provider.keyURLArg)
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
