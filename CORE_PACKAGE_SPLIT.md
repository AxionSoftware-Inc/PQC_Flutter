# Hardened Core Package Split

## What changed

- `packages/crypto_core` now holds the crypto and durability engine.
- `packages/chat_core` now holds chat orchestration and state flow.
- App-side old paths in `lib/core/*`, `lib/features/crypto/*`, `lib/features/chat/*`, and `lib/features/security/*` are thin shim exports.
- UI/app code can keep its current imports for now, but the real implementation lives in package code.

## Why this is safer

- Flutter/UI/theme refactors no longer require touching real crypto/chat engine files.
- Package internals are isolated under `src/`, so future work has a clearer boundary.
- We added a boundary test to catch direct `package:.../src/...` imports from app/test code.

## Practical rule

- UI, screens, controllers, and app wiring should talk to `chat_core`.
- Chat core talks to `crypto_core`.
- If you need to change crypto durability, legacy decrypt, key lifecycle, or group/private encryption, do it in `packages/crypto_core`.
- If you need to change send/sync/retry/trust orchestration, do it in `packages/chat_core`.
- If you need to change visuals, branding, layout, spacing, or navigation, stay in app/UI code.

## Current migration shape

- This split is intentionally staged.
- Existing app imports still work through shim files so the project does not need a risky all-at-once rewrite.
- Composition root and some platform/infrastructure pieces still live in the app layer.

## Stability policy

- Legacy decrypt support must remain additive only.
- New payload writers can be added, but existing decrypt readers should not be removed.
- App code must not import `package:crypto_core/src/...` or `package:chat_core/src/...` directly.
