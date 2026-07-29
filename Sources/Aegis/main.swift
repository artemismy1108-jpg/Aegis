import Foundation

struct AegisConfig: Codable {
    var providers: [String: ProviderConfig]
    var profiles: [String: ProfileConfig]
    var watchedModels: [WatchedModel]
}

struct ProviderConfig: Codable {
    var baseURL: String
    var apiKeyEnv: String
    var keyAlias: String?
    var defaultModel: String?
    var dashboardURL: String?
    var billingURL: String?
    var keyURL: String?
    var configPaths: [String]
}

struct ProfileConfig: Codable {
    var provider: String
    var model: String
}

struct WatchedModel: Codable {
    var id: String
    var alias: String
    var minContext: Int
    var mustSupport: [String]
    var notifyWhenSavingPct: Double
}

struct OpenRouterModelsResponse: Codable {
    var data: [OpenRouterModel]
}

struct OpenRouterModel: Codable {
    var id: String
    var name: String?
    var contextLength: Int?
    var pricing: Pricing
    var supportedParameters: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case contextLength = "context_length"
        case pricing
        case supportedParameters = "supported_parameters"
    }
}

struct Pricing: Codable {
    var prompt: String
    var completion: String
}

struct OpenRouterCreditsResponse: Codable {
    var data: OpenRouterCreditsData
}

struct OpenRouterCreditsData: Codable {
    var totalCredits: Double
    var totalUsage: Double

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }

    var balance: Double { max(0, totalCredits - totalUsage) }
    var usedPercent: Double {
        totalCredits > 0 ? min(100, totalUsage / totalCredits * 100) : 0
    }
}

struct OpenRouterKeyResponse: Codable {
    var data: OpenRouterKeyData
}

struct OpenRouterKeyData: Codable {
    var limit: Double?
    var usage: Double?
    var usageDaily: Double?
    var usageWeekly: Double?
    var usageMonthly: Double?

    enum CodingKeys: String, CodingKey {
        case limit
        case usage
        case usageDaily = "usage_daily"
        case usageWeekly = "usage_weekly"
        case usageMonthly = "usage_monthly"
    }
}

enum AegisError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())

do {
    try run(args)
} catch {
    fputs("aegis: \(error)\n", stderr)
    exit(1)
}

func run(_ args: [String]) throws {
    switch args.first {
    case nil, "help", "--help", "-h":
        printHelp()
    case "init-sample":
        try writeSampleConfig()
    case "setup":
        try runSetup()
    case "status":
        let config = try loadConfig()
        printStatus(config)
    case "export":
        let config = try loadConfig()
        let exportArgs = Array(args.dropFirst())
        let target = exportArgs.first { !$0.hasPrefix("-") } ?? "env"
        try printExport(config, target: target, withSecrets: exportArgs.contains("--with-secrets"))
    case "price-watch":
        let config = try loadConfig()
        let models = try loadOpenRouterModels(args: args)
        printPriceWatch(config: config, models: models)
    case "usage":
        let config = try loadConfig()
        try printUsage(config: config, args: Array(args.dropFirst()))
    case "scan":
        let config = try loadConfig()
        printConfigScan(config, suggest: args.contains("--suggest"))
    case "doctor":
        try runDoctor()
    case "open":
        let config = try loadConfig()
        try runOpen(config: config, args: Array(args.dropFirst()))
    case "key":
        try runKeyCommand(Array(args.dropFirst()))
    default:
        throw AegisError.message("unknown command '\(args.first!)'")
    }
}

func printHelp() {
    print("""
    Aegis - macOS command center for LLM keys, spend, routes, and config

    Usage:
      aegis init-sample
      aegis setup
      aegis status
      aegis export [env|json|codex|workbuddy] [--with-secrets]
      aegis price-watch [models.json]
      aegis usage openrouter
      aegis scan [--suggest]
      aegis doctor
      aegis open <provider> [dashboard|billing|keys]
      aegis key set <provider> <alias>
      aegis key list
      aegis key reveal <provider> <alias>
      aegis key delete <provider> <alias>

    Config:
      ~/.config/aegis/config.json
    """)
}

func configURL() -> URL {
    if let override = ProcessInfo.processInfo.environment["AEGIS_CONFIG"] {
        return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
    }
    let home = ProcessInfo.processInfo.environment["HOME"]
        .map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".config/aegis/config.json")
}

func loadConfig() throws -> AegisConfig {
    let url = configURL()
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw AegisError.message("missing config at \(url.path); run 'aegis setup'")
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(AegisConfig.self, from: data)
}

func writeSampleConfig() throws {
    let url = configURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: url.path) {
        throw AegisError.message("config already exists at \(url.path)")
    }

    let sample = AegisConfig(
        providers: [
            "openai": ProviderConfig(
                baseURL: "https://api.openai.com/v1",
                apiKeyEnv: "OPENAI_API_KEY",
                keyAlias: "personal",
                defaultModel: "gpt-4.1",
                dashboardURL: "https://platform.openai.com/usage",
                billingURL: "https://platform.openai.com/settings/organization/billing/overview",
                keyURL: "https://platform.openai.com/api-keys",
                configPaths: ["~/.zshrc", "~/.config/codex/config.toml"]
            ),
            "gemini": ProviderConfig(
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                apiKeyEnv: "GEMINI_API_KEY",
                keyAlias: "personal",
                defaultModel: "gemini-2.5-pro",
                dashboardURL: "https://aistudio.google.com/",
                billingURL: "https://console.cloud.google.com/billing",
                keyURL: "https://aistudio.google.com/app/apikey",
                configPaths: ["~/.zshrc"]
            ),
            "openrouter": ProviderConfig(
                baseURL: "https://openrouter.ai/api/v1",
                apiKeyEnv: "OPENROUTER_API_KEY",
                keyAlias: "personal",
                defaultModel: "anthropic/claude-sonnet-4",
                dashboardURL: "https://openrouter.ai/activity",
                billingURL: "https://openrouter.ai/credits",
                keyURL: "https://openrouter.ai/settings/keys",
                configPaths: ["~/.zshrc", "~/.config/aegis/config.json"]
            ),
            "minimax": ProviderConfig(
                baseURL: "https://api.minimax.chat/v1",
                apiKeyEnv: "MINIMAX_API_KEY",
                keyAlias: "personal",
                defaultModel: "MiniMax-M1",
                dashboardURL: "https://platform.minimaxi.com/",
                billingURL: "https://platform.minimaxi.com/",
                keyURL: "https://platform.minimaxi.com/",
                configPaths: ["~/.zshrc"]
            )
        ],
        profiles: [
            "coding": ProfileConfig(provider: "openrouter", model: "anthropic/claude-sonnet-4"),
            "cheap-coding": ProfileConfig(provider: "openrouter", model: "qwen/qwen3-coder")
        ],
        watchedModels: [
            WatchedModel(
                id: "anthropic/claude-sonnet-4",
                alias: "coding",
                minContext: 64000,
                mustSupport: ["tools"],
                notifyWhenSavingPct: 20
            )
        ]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(sample).write(to: url, options: .atomic)
    print("wrote \(url.path)")
}

func runSetup() throws {
    let url = configURL()
    if FileManager.default.fileExists(atPath: url.path) {
        print("config exists: \(url.path)")
    } else {
        try writeSampleConfig()
    }

    let config = try loadConfig()
    print("")
    printStatus(config)
    print("")
    printConfigScan(config, suggest: true)
}

func runDoctor() throws {
    print("Aegis doctor")
    print("")

    let url = configURL()
    print("config: \(FileManager.default.fileExists(atPath: url.path) ? url.path : "missing at \(url.path)")")

    guard FileManager.default.fileExists(atPath: url.path) else {
        print("next: aegis setup")
        return
    }

    let config = try loadConfig()
    print("")
    print("providers")
    printStatus(config)
    print("")
    print("scan")
    printConfigScan(config, suggest: false)
    print("")
    print("exports")
    print("- safe codex: ready")
    print("- safe workbuddy: ready")
    let secretReady = config.profiles.values.allSatisfy { profile in
        guard let provider = config.providers[profile.provider] else { return false }
        return keychainHasKey(provider: profile.provider, alias: provider.keyAlias ?? "default")
    }
    print("- secret profile export: \(secretReady ? "ready" : "missing profile Keychain key")")
    print("")
    print("openrouter")
    if let provider = config.providers["openrouter"] {
        let envReady = recognizedAPIKeyEnvs(providerName: "openrouter", provider: provider)
            .contains { ProcessInfo.processInfo.environment[$0] != nil }
        let keyReady = keychainHasKey(provider: "openrouter", alias: provider.keyAlias ?? "default")
        print("- credentials: \(envReady || keyReady ? "ready" : "missing")")
        print("- usage: aegis usage openrouter")
        print("- price watch: aegis price-watch")
    } else {
        print("- provider missing")
    }
}

func runOpen(config: AegisConfig, args: [String]) throws {
    guard let providerName = args.first else {
        throw AegisError.message("usage: aegis open <provider> [dashboard|billing|keys]")
    }
    let target = args.dropFirst().first ?? "dashboard"
    guard let provider = config.providers[providerName] else {
        throw AegisError.message("unknown provider '\(providerName)'")
    }

    let rawURL: String?
    switch target {
    case "dashboard":
        rawURL = provider.dashboardURL
    case "billing":
        rawURL = provider.billingURL
    case "keys", "key":
        rawURL = provider.keyURL
    default:
        throw AegisError.message("unknown open target '\(target)'")
    }

    guard let url = rawURL, !url.isEmpty else {
        throw AegisError.message("\(providerName) has no \(target) URL configured")
    }
    try openURL(url)
}

func openURL(_ url: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw AegisError.message("failed to open \(url)")
    }
}

func printStatus(_ config: AegisConfig) {
    for name in config.providers.keys.sorted() {
        guard let provider = config.providers[name] else { continue }
        let envs = recognizedAPIKeyEnvs(providerName: name, provider: provider)
        let keyState = providerCredentialState(providerName: name, provider: provider, envs: envs)
        let model = provider.defaultModel ?? "-"
        print("\(name): \(keyState), model \(model), env \(envs.joined(separator: "|"))")
    }
}

func providerCredentialState(providerName: String, provider: ProviderConfig, envs: [String]) -> String {
    if envs.contains(where: { ProcessInfo.processInfo.environment[$0] != nil }) {
        return "env ready"
    }

    let alias = provider.keyAlias ?? "default"
    if keychainHasKey(provider: providerName, alias: alias) {
        return "keychain ready (\(alias))"
    }

    return "missing key"
}

func recognizedAPIKeyEnvs(providerName: String, provider: ProviderConfig) -> [String] {
    switch providerName {
    case "openai":
        return ["OPENAI_ADMIN_KEY", "OPENAI_API_KEY"]
    case "minimax":
        return ["MINIMAX_CODING_API_KEY", "MINIMAX_API_KEY"]
    default:
        return [provider.apiKeyEnv]
    }
}

func printExport(_ config: AegisConfig, target: String, withSecrets: Bool) throws {
    switch target {
    case "env":
        for name in config.providers.keys.sorted() {
            guard let provider = config.providers[name] else { continue }
            let value = withSecrets ? try keychainSecret(providerName: name, provider: provider) : ""
            print("# \(name)")
            print("export \(provider.apiKeyEnv)=\(shellQuote(value))")
        }
    case "json":
        if withSecrets {
            throw AegisError.message("json export does not support --with-secrets; use env, codex, or workbuddy")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(config), encoding: .utf8)!)
    case "codex", "workbuddy":
        for profileName in config.profiles.keys.sorted() {
            guard let profile = config.profiles[profileName],
                  let provider = config.providers[profile.provider] else { continue }
            print("[profiles.\(profileName)]")
            print("provider = \"\(profile.provider)\"")
            print("model = \"\(profile.model)\"")
            print("base_url = \"\(provider.baseURL)\"")
            print("api_key_env = \"\(provider.apiKeyEnv)\"")
            if withSecrets {
                print("api_key = \"\(tomlEscape(try keychainSecret(providerName: profile.provider, provider: provider)))\"")
            }
            print("")
        }
    default:
        throw AegisError.message("unknown export target '\(target)'")
    }
}

func keychainSecret(providerName: String, provider: ProviderConfig) throws -> String {
    let alias = provider.keyAlias ?? "default"
    do {
        return try keychainReveal(provider: providerName, alias: alias)
    } catch {
        throw AegisError.message(
            "missing Keychain key \(providerName)/\(alias); store it with: printf '%s' \"$\(provider.apiKeyEnv)\" | aegis key set \(providerName) \(alias)")
    }
}

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func tomlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}

func loadOpenRouterModels(args: [String]) throws -> [OpenRouterModel] {
    if args.count > 1 {
        let url = URL(fileURLWithPath: NSString(string: args[1]).expandingTildeInPath)
        return try JSONDecoder().decode(OpenRouterModelsResponse.self, from: Data(contentsOf: url)).data
    }

    guard let url = URL(string: "https://openrouter.ai/api/v1/models?sort=pricing-low-to-high") else {
        throw AegisError.message("invalid OpenRouter models URL")
    }
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Data, Error>!
    URLSession.shared.dataTask(with: url) { data, _, error in
        if let error = error {
            result = .failure(error)
        } else {
            result = .success(data ?? Data())
        }
        semaphore.signal()
    }.resume()
    semaphore.wait()
    return try JSONDecoder().decode(OpenRouterModelsResponse.self, from: try result.get()).data
}

func printPriceWatch(config: AegisConfig, models: [OpenRouterModel]) {
    let index = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
    for watched in config.watchedModels {
        guard let current = index[watched.id] else {
            print("\(watched.alias): current model not found (\(watched.id))")
            continue
        }
        let currentCost = tokenCost(current)
        let candidates = models
            .filter { $0.id != current.id }
            .filter { ($0.contextLength ?? 0) >= watched.minContext }
            .filter { supports($0, watched.mustSupport) }
            .compactMap { model -> (OpenRouterModel, Double)? in
                let saving = savingPercent(currentCost: currentCost, candidateCost: tokenCost(model))
                return saving >= watched.notifyWhenSavingPct ? (model, saving) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3)

        if candidates.isEmpty {
            print("\(watched.alias): no cheaper route over \(Int(watched.notifyWhenSavingPct))%")
            continue
        }

        print("\(watched.alias): \(current.id)")
        for (model, saving) in candidates {
            print("  -> \(model.id) saves \(Int(saving.rounded()))%")
        }
    }
}

func printUsage(config: AegisConfig, args: [String]) throws {
    guard args.first == "openrouter" else {
        throw AegisError.message("usage: aegis usage openrouter")
    }
    guard let provider = config.providers["openrouter"] else {
        throw AegisError.message("openrouter provider is not configured")
    }
    let apiKey = try providerAPIKey(providerName: "openrouter", provider: provider)
    let credits = try fetchOpenRouterCredits(baseURL: provider.baseURL, apiKey: apiKey)
    let key = try? fetchOpenRouterKey(baseURL: provider.baseURL, apiKey: apiKey)

    print("OpenRouter")
    print("  balance: \(money(credits.data.balance))")
    print("  total credits: \(money(credits.data.totalCredits))")
    print("  total usage: \(money(credits.data.totalUsage)) (\(percent(credits.data.usedPercent)))")
    if let key = key?.data {
        if let daily = key.usageDaily { print("  today: \(money(daily))") }
        if let weekly = key.usageWeekly { print("  week: \(money(weekly))") }
        if let monthly = key.usageMonthly { print("  month: \(money(monthly))") }
        if let limit = key.limit, let usage = key.usage {
            print("  key limit: \(money(usage)) / \(money(limit))")
        }
    }
}

func printConfigScan(_ config: AegisConfig, suggest: Bool) {
    let envsByProvider = Dictionary(uniqueKeysWithValues: config.providers.map { name, provider in
        (name, recognizedAPIKeyEnvs(providerName: name, provider: provider))
    })
    let paths = Array(Set(config.providers.values.flatMap(\.configPaths) + commonConfigPaths())).sorted()
    var foundProviders = Set<String>()

    for rawPath in paths {
        let path = NSString(string: rawPath).expandingTildeInPath
        let exists = FileManager.default.fileExists(atPath: path)
        guard exists else {
            print("\(rawPath): missing")
            continue
        }

        let text = (try? String(contentsOfFile: path)) ?? ""
        let hits = envsByProvider
            .flatMap { provider, envs in envs.filter { text.contains($0) }.map { "\(provider):\($0)" } }
            .sorted()
        hits.forEach { hit in
            if let provider = hit.split(separator: ":").first {
                foundProviders.insert(String(provider))
            }
        }
        if hits.isEmpty {
            print("\(rawPath): exists")
        } else {
            print("\(rawPath): \(hits.joined(separator: ", "))")
        }
    }

    if suggest {
        print("")
        print("Suggestions")
        for providerName in config.providers.keys.sorted() {
            guard let provider = config.providers[providerName] else { continue }
            let alias = provider.keyAlias ?? "default"
            let env = provider.apiKeyEnv
            if foundProviders.contains(providerName) {
                print("- Store \(providerName) in Keychain: printf '%s' \"$\((env))\" | aegis key set \(providerName) \(alias)")
            } else {
                print("- Add \(providerName) env or Keychain key: aegis key set \(providerName) \(alias)")
            }
        }
        print("- Export safe config: aegis export codex")
        print("- Export with secrets after review: aegis export codex --with-secrets")
    }
}

func commonConfigPaths() -> [String] {
    [
        "~/.zshrc",
        "~/.zprofile",
        "~/.bashrc",
        "~/.bash_profile",
        "~/.profile",
        "~/.env",
        "~/.config/aegis/config.json",
        "~/.config/codex/config.toml",
        "~/.codex/config.toml",
        "~/.config/workbuddy/config.toml",
        "~/.workbuddy/config.toml"
    ]
}

func providerAPIKey(providerName: String, provider: ProviderConfig) throws -> String {
    for env in recognizedAPIKeyEnvs(providerName: providerName, provider: provider) {
        if let raw = ProcessInfo.processInfo.environment[env]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            return raw
        }
    }
    return try keychainSecret(providerName: providerName, provider: provider)
}

func fetchOpenRouterCredits(baseURL: String, apiKey: String) throws -> OpenRouterCreditsResponse {
    try fetchOpenRouter(path: "credits", baseURL: baseURL, apiKey: apiKey)
}

func fetchOpenRouterKey(baseURL: String, apiKey: String) throws -> OpenRouterKeyResponse {
    try fetchOpenRouter(path: "key", baseURL: baseURL, apiKey: apiKey)
}

func fetchOpenRouter<T: Decodable>(path: String, baseURL: String, apiKey: String) throws -> T {
    guard let url = URL(string: baseURL)?.appendingPathComponent(path) else {
        throw AegisError.message("invalid OpenRouter base URL: \(baseURL)")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Aegis", forHTTPHeaderField: "X-Title")

    let data = try httpData(request)
    return try JSONDecoder().decode(T.self, from: data)
}

func httpData(_ request: URLRequest) throws -> Data {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<(Data, URLResponse), Error>!
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            result = .failure(error)
        } else {
            result = .success((data ?? Data(), response ?? URLResponse()))
        }
        semaphore.signal()
    }.resume()
    semaphore.wait()

    let (data, response) = try result.get()
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw AegisError.message("HTTP \(http.statusCode)")
    }
    return data
}

func money(_ value: Double) -> String {
    String(format: "$%.2f", value)
}

func percent(_ value: Double) -> String {
    String(format: "%.1f%%", value)
}

func supports(_ model: OpenRouterModel, _ required: [String]) -> Bool {
    let supported = Set(model.supportedParameters ?? [])
    return required.allSatisfy { supported.contains($0) }
}

func tokenCost(_ model: OpenRouterModel) -> Double {
    (Double(model.pricing.prompt) ?? 0) + (Double(model.pricing.completion) ?? 0)
}

func savingPercent(currentCost: Double, candidateCost: Double) -> Double {
    guard currentCost > 0, candidateCost < currentCost else { return 0 }
    return (currentCost - candidateCost) / currentCost * 100
}

func runKeyCommand(_ args: [String]) throws {
    switch args.first {
    case "set":
        guard args.count == 3 else { throw AegisError.message("usage: aegis key set <provider> <alias>") }
        let secret = readStdin().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            throw AegisError.message("pipe the API key on stdin, e.g. printf '%s' \"$OPENROUTER_API_KEY\" | aegis key set openrouter personal")
        }
        try keychainSet(provider: args[1], alias: args[2], secret: secret)
        print("stored \(args[1])/\(args[2]) in Keychain")
    case "list":
        try keychainList()
    case "reveal":
        guard args.count == 3 else { throw AegisError.message("usage: aegis key reveal <provider> <alias>") }
        print(try keychainReveal(provider: args[1], alias: args[2]))
    case "delete":
        guard args.count == 3 else { throw AegisError.message("usage: aegis key delete <provider> <alias>") }
        try keychainDelete(provider: args[1], alias: args[2])
        print("deleted \(args[1])/\(args[2]) from Keychain")
    default:
        throw AegisError.message("usage: aegis key [set|list|reveal|delete]")
    }
}

func readStdin() -> String {
    String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func keychainService(provider: String) -> String {
    "aegis.\(provider)"
}

func keychainRun(_ args: [String], input: String? = nil, allowFailure: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = args

    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    if let input = input {
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
    } else {
        try process.run()
    }

    process.waitUntilExit()
    let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if process.terminationStatus != 0, !allowFailure {
        throw AegisError.message(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return stdout
}

func keychainSet(provider: String, alias: String, secret: String) throws {
    _ = try keychainRun([
        "add-generic-password",
        "-U",
        "-s", keychainService(provider: provider),
        "-a", alias,
        "-w", secret
    ])
}

func keychainReveal(provider: String, alias: String) throws -> String {
    try keychainRun([
        "find-generic-password",
        "-s", keychainService(provider: provider),
        "-a", alias,
        "-w"
    ]).trimmingCharacters(in: .newlines)
}

func keychainDelete(provider: String, alias: String) throws {
    _ = try keychainRun([
        "delete-generic-password",
        "-s", keychainService(provider: provider),
        "-a", alias
    ])
}

func keychainHasKey(provider: String, alias: String) -> Bool {
    (try? keychainRun([
        "find-generic-password",
        "-s", keychainService(provider: provider),
        "-a", alias
    ], allowFailure: true)).map { !$0.isEmpty } ?? false
}

func keychainList() throws {
    let providers = ["gemini", "minimax", "openai", "openrouter"]
    var found = false
    for provider in providers {
        let output = try keychainRun([
            "find-generic-password",
            "-s", keychainService(provider: provider)
        ], allowFailure: true)
        for line in output.split(separator: "\n") where line.contains("\"acct\"") {
            let alias = line
                .replacingOccurrences(of: #"^\s*"acct"<blob>="#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            print("\(provider)/\(alias)")
            found = true
        }
    }
    if !found { print("no Aegis keys in Keychain") }
}
