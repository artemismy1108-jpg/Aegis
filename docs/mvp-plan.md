# Aegis MVP Plan

## Phase 1: Upstream Intake

- Clone or fork CodexBar.
- Build it unchanged.
- Identify provider clients, menu UI, CLI entry points, config storage, and tests.
- Decide whether to fork in place or port pieces into a clean Aegis app.

## Phase 2: Rebrand And Scope

- Rename visible app strings to Aegis.
- Rename CLI command to `aegis`.
- Use `~/.config/aegis/` for non-secret metadata.
- Use `aegis.<provider>.<alias>` as the Keychain namespace.
- Hide or remove providers outside OpenAI, Gemini, OpenRouter, and MiniMax.

## Phase 3: Vault

- Add key metadata model.
- Store secrets in Keychain.
- Gate reveal, copy, and secret export with LocalAuthentication.
- Mask keys in UI and logs.

## Phase 4: Export

- Implement safe export first:
  - Codex
  - WorkBuddy
  - `.env`
  - shell
  - JSON
  - TOML
- Add secret export only after authentication works.

## Phase 5: OpenRouter Price Watch

- Fetch OpenRouter model pricing.
- Store watched models and minimum requirements.
- Compare current model with cheaper candidates.
- Show alerts only when saving exceeds the configured threshold.
- Export cheaper route config for Codex and WorkBuddy.

## Verification

- Build macOS app.
- Run existing tests.
- Add one focused check per new non-trivial module.
- Manually test Touch ID fallback and key masking.

