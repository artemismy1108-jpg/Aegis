# Aegis Requirements

## Goal

Build a practical macOS menu bar app for an algorithm engineer who uses several
LLM providers daily and needs one place to see spend, manage keys, export config,
and notice cheaper OpenRouter routes.

## Supported Providers

- OpenAI
- Gemini
- OpenRouter
- MiniMax

## Core Features

### Provider Status

Show per-provider status in the menu bar popover:

- balance, when available
- today spend, when available
- month spend, when available
- key count
- config status
- direct links to dashboard, billing, API keys, and docs

### Secure Key Vault

Store API key secrets in macOS Keychain.

Keep only metadata in normal app config:

- provider
- alias
- organization or project
- env var name
- config file paths
- dashboard URLs
- keychain service/account identifiers

Require Touch ID or system password for:

- opening the key vault page
- revealing a key
- copying a key
- exporting a config that includes raw secrets

Keys must be masked by default, excluded from logs, and never written to crash
reports or plain config files.

### Config Export

Export configuration for:

- Codex
- WorkBuddy
- `.env`
- shell `export`
- JSON
- TOML

Default mode is safe export: env var references only, no raw secrets.

Secret export is allowed only after local authentication.

### OpenRouter Price Watch

Track user-selected OpenRouter models and recommend cheaper alternatives only
when they satisfy the selected requirements:

- minimum context length
- tools support
- structured output support
- reasoning support, when needed
- image input support, when needed
- minimum saving percentage

The menu bar should show a price alert only for meaningful savings, not every
minor price difference.

## Non-Goals For MVP

- Automatic model switching inside third-party tools
- Cloud sync
- Team sharing
- Full billing reconciliation
- Support for every provider CodexBar supports

