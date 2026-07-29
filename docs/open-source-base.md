# Open Source Base Evaluation

## Preferred Base: CodexBar

Repository: `https://github.com/steipete/CodexBar`

Local reference copy: `CodexBar/` is ignored by git and used only for upstream
inspection.

Why it is the best starting point:

- macOS menu bar shape already exists
- provider usage and quota concepts already exist
- OpenRouter, OpenAI, and Gemini are likely close to existing supported flows
- CLI and JSON output ideas map well to `aegis status` and `aegis export`
- less code to invent before the product is useful

Expected Aegis changes:

- Rebrand app, CLI, config directory, and Keychain namespace
- Narrow provider list to OpenAI, Gemini, OpenRouter, MiniMax
- Add MiniMax if missing
- Add secure key metadata management
- Add Touch ID-gated key reveal/copy/export
- Add Codex and WorkBuddy config exporters
- Add OpenRouter price watch and cheaper route recommendations

Upstream notes already adopted into the Aegis CLI:

- OpenRouter uses `OPENROUTER_API_KEY` and base URL `https://openrouter.ai/api/v1`.
- OpenAI should recognize both `OPENAI_ADMIN_KEY` and `OPENAI_API_KEY`.
- MiniMax should recognize `MINIMAX_CODING_API_KEY` before `MINIMAX_API_KEY`.
- OpenRouter usage can come from `/credits` and `/key`; price watch uses `/models`.

## Reference Projects

### ClaudeBar

Useful mainly for native SwiftUI menu bar UX and quota presentation patterns.
Less ideal as the base because it is more Claude/Codex-centric.

### opencode-bar

Useful for pay-as-you-go and quota status menu organization. Good reference for
how to separate balance, spend, and projected month-end cost.

### TokenTracker

Useful for local scanning ideas across many AI tools. Good reference for config
file discovery, but broader than the Aegis MVP.

## Decision

Start from CodexBar if it clones and builds cleanly. If it is too coupled, keep a
small Aegis app and port only specific provider clients or CLI patterns.
