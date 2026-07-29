import Foundation

struct AegisConfig: Codable {
    var providers: [String: ProviderConfig]
    var profiles: [String: ProfileConfig]
    var watchedModels: [WatchedModel]
}

struct ProviderConfig: Codable {
    var baseURL: String
    var apiKeyEnv: String
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
    case "status":
        let config = try loadConfig()
        printStatus(config)
    case "export":
        let config = try loadConfig()
        let target = args.dropFirst().first ?? "env"
        try printExport(config, target: target)
    case "price-watch":
        let config = try loadConfig()
        let models = try loadOpenRouterModels(args: args)
        printPriceWatch(config: config, models: models)
    default:
        throw AegisError.message("unknown command '\(args.first!)'")
    }
}

func printHelp() {
    print("""
    Aegis - macOS command center for LLM keys, spend, routes, and config

    Usage:
      aegis init-sample
      aegis status
      aegis export [env|json|codex|workbuddy]
      aegis price-watch [models.json]

    Config:
      ~/.config/aegis/config.json
    """)
}

func configURL() -> URL {
    if let override = ProcessInfo.processInfo.environment["AEGIS_CONFIG"] {
        return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".config/aegis/config.json")
}

func loadConfig() throws -> AegisConfig {
    let url = configURL()
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw AegisError.message("missing config at \(url.path); run 'aegis init-sample'")
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
                defaultModel: "gpt-4.1",
                dashboardURL: "https://platform.openai.com/usage",
                billingURL: "https://platform.openai.com/settings/organization/billing/overview",
                keyURL: "https://platform.openai.com/api-keys",
                configPaths: ["~/.zshrc", "~/.config/codex/config.toml"]
            ),
            "gemini": ProviderConfig(
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                apiKeyEnv: "GEMINI_API_KEY",
                defaultModel: "gemini-2.5-pro",
                dashboardURL: "https://aistudio.google.com/",
                billingURL: "https://console.cloud.google.com/billing",
                keyURL: "https://aistudio.google.com/app/apikey",
                configPaths: ["~/.zshrc"]
            ),
            "openrouter": ProviderConfig(
                baseURL: "https://openrouter.ai/api/v1",
                apiKeyEnv: "OPENROUTER_API_KEY",
                defaultModel: "anthropic/claude-sonnet-4",
                dashboardURL: "https://openrouter.ai/activity",
                billingURL: "https://openrouter.ai/credits",
                keyURL: "https://openrouter.ai/settings/keys",
                configPaths: ["~/.zshrc", "~/.config/aegis/config.json"]
            ),
            "minimax": ProviderConfig(
                baseURL: "https://api.minimax.chat/v1",
                apiKeyEnv: "MINIMAX_API_KEY",
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

func printStatus(_ config: AegisConfig) {
    for name in config.providers.keys.sorted() {
        guard let provider = config.providers[name] else { continue }
        let keyState = ProcessInfo.processInfo.environment[provider.apiKeyEnv] == nil ? "missing env" : "env ready"
        let model = provider.defaultModel ?? "-"
        print("\(name): \(keyState), model \(model), env \(provider.apiKeyEnv)")
    }
}

func printExport(_ config: AegisConfig, target: String) throws {
    switch target {
    case "env":
        for name in config.providers.keys.sorted() {
            guard let provider = config.providers[name] else { continue }
            print("# \(name)")
            print("export \(provider.apiKeyEnv)=\"\"")
        }
    case "json":
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
            print("")
        }
    default:
        throw AegisError.message("unknown export target '\(target)'")
    }
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

