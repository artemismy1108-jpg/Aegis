import AppKit
import Foundation

final class AegisMenuApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private lazy var controller = AegisPanelController(aegisPath: aegisPath, priceFixturePath: priceFixturePath)

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
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.contentViewController = controller
        controller.refresh()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        controller.refresh()
        refreshStatusTitle()
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func refreshStatusTitle() {
        let ready = controller.providerStatus
            .split(separator: "\n")
            .filter { $0.contains("ready") }
            .count
        statusItem.button?.title = ready > 0 ? "Aegis \(ready)/4" : "Aegis"
    }
}

final class AegisPanelController: NSViewController {
    private let aegisPath: String
    private let priceFixturePath: String?
    private let root = NSStackView()

    private(set) var providerStatus = ""

    init(aegisPath: String, priceFixturePath: String?) {
        self.aegisPath = aegisPath
        self.priceFixturePath = priceFixturePath
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 520))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16)
        ])
    }

    func refresh() {
        root.arrangedSubviews.forEach { $0.removeFromSuperview() }

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
        root.addArrangedSubview(section(title: "Providers", body: providerStatus, maxLines: 6))
        root.addArrangedSubview(section(title: "OpenRouter", body: usage, maxLines: 4))
        root.addArrangedSubview(section(title: "Price Watch", body: prices, maxLines: 4))
        root.addArrangedSubview(section(title: "Config Scan", body: scan, maxLines: 4))
        root.addArrangedSubview(actionsGrid())
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

        let title = label("Aegis", font: .systemFont(ofSize: 22, weight: .semibold))
        let subtitle = label("LLM keys, spend, routes, and config", color: .secondaryLabelColor)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        return stack
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
            box.widthAnchor.constraint(equalToConstant: 388),
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
            ("Refresh", { [weak self] in self?.refresh() }),
            ("Setup", { [weak self] in self?.showCommand("Setup", ["setup"]) }),
            ("Doctor", { [weak self] in self?.showCommand("Doctor", ["doctor"]) }),
        ])
        let row2 = buttonRow([
            ("Scan", { [weak self] in self?.showCommand("Scan Suggestions", ["scan", "--suggest"]) }),
            ("Copy Codex", { [weak self] in self?.copyCommand(["export", "codex"]) }),
            ("OR Keys", { [weak self] in self?.runSilent(["open", "openrouter", "keys"]) })
        ])
        let row3 = buttonRow([
            ("OpenAI Bill", { [weak self] in self?.runSilent(["open", "openai", "billing"]) }),
            ("Gemini Keys", { [weak self] in self?.runSilent(["open", "gemini", "keys"]) }),
            ("MiniMax", { [weak self] in self?.runSilent(["open", "minimax", "dashboard"]) }),
        ])
        let row4 = buttonRow([
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
            button.widthAnchor.constraint(equalToConstant: 124).isActive = true
            row.addArrangedSubview(button)
        }
        return row
    }

    private func showCommand(_ title: String, _ args: [String]) {
        showOutput(title: title, output: runAegis(args))
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

let app = NSApplication.shared
let delegate = AegisMenuApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
