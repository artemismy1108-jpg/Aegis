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

