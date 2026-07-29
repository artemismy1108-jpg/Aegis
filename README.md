# Aegis

Aegis is a macOS menu bar command center for LLM keys, spend, routes, and config.

It is planned as a pragmatic fork/adaptation of existing open-source macOS LLM
usage monitors, with CodexBar as the preferred base once the upstream repository
is available locally.

## MVP Scope

- Providers: OpenAI, Gemini, OpenRouter, MiniMax
- Local-first API key vault backed by macOS Keychain
- Touch ID or system password before reveal, copy, or secret export
- Usage and spend monitoring where provider APIs allow it
- OpenRouter price watch for cheaper equivalent models
- One-click config export for Codex, WorkBuddy, `.env`, shell, JSON, and TOML

## Product Shape

Aegis should feel like a developer utility, not a dashboard:

- Menu bar first
- Dense but calm provider status rows
- Sensitive actions behind authentication
- Safe config export by default
- Price alerts only when switching is meaningfully cheaper

## Repository Strategy

Preferred path:

1. Fork or clone `steipete/CodexBar`.
2. Rename app, bundle identifiers, config paths, and CLI commands to Aegis.
3. Remove providers outside the MVP unless keeping them costs less than deleting them.
4. Add the vault, config export, and OpenRouter price-watch features.

Fallback path:

If CodexBar is too coupled or hard to rebrand, keep this repo as a clean SwiftUI
MenuBarExtra app and port only provider clients and CLI ideas from CodexBar.

## Current Developer Preview

The repo currently includes a small `aegis` CLI core while the CodexBar upstream
intake is blocked by local GitHub DNS/SSH-agent issues in the Codex environment.

Build:

```bash
make build
```

Try the safe local flow:

```bash
AEGIS_CONFIG=/private/tmp/aegis-config.json .build/aegis setup
AEGIS_CONFIG=/private/tmp/aegis-config.json .build/aegis status
AEGIS_CONFIG=/private/tmp/aegis-config.json .build/aegis export codex
AEGIS_CONFIG=/private/tmp/aegis-config.json .build/aegis price-watch Fixtures/openrouter-models.sample.json
```

This preview intentionally exports env-var references, not raw API keys.

OpenRouter usage:

```bash
.build/aegis usage openrouter
```

The command reads `OPENROUTER_API_KEY` first, then falls back to the configured
Keychain alias. It fetches `/credits` for balance and `/key` for daily, weekly,
monthly, and key-limit usage when OpenRouter returns those fields.

Local config scan:

```bash
.build/aegis scan --suggest
```

`scan` checks configured paths such as `~/.zshrc` and `~/.config/codex/config.toml`
and reports which provider env names are mentioned. It never prints the env
values. `--suggest` adds next-step commands for storing discovered providers in
Keychain and exporting config.

Secret export is explicit:

```bash
.build/aegis export codex --with-secrets
.build/aegis export workbuddy --with-secrets
.build/aegis export env --with-secrets
```

`--with-secrets` reads the provider's `keyAlias` from Keychain. Missing keys fail
the export instead of producing a partial config.

Keychain-backed local vault:

```bash
printf '%s' "$OPENROUTER_API_KEY" | .build/aegis key set openrouter personal
.build/aegis key list
.build/aegis key reveal openrouter personal
.build/aegis key delete openrouter personal
```

`key reveal` prints the secret, so use it only in a trusted terminal. The future
menu bar app should gate reveal/copy/export with Touch ID or system password.
