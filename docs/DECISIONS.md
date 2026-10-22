# Decision record — 2026-10-22: Scope approval

**Decision: APPROVED.** The complete EReader roadmap, including all 18 additional feature candidates ER-017–ER-034, is approved for staged development.

- Platforms: Windows and Android, Flutter shared UI.
- Development order: M0 → M1 → M2 → M3 → M4 → M5 → M6.
- P0 first: Flutter bootstrap and local reader/TTS foundation; subsequent increments must preserve working local-only operation.
- Lower-priority features are approved for the roadmap, **not** pulled into the MVP or considered already delivered.
- Only progress milestone status when corresponding code, real builds and tests have evidence; Flutter generated platform runners and native builds need SDK/toolchains.
- Offline-first, no mandatory backend/account; explicit consent for cloud book text, API usage budgets, no DRM bypass, accessiblity and stable anchors.
- Avoid speculative timeline promises and use feature branches/PRs for implementation changes.

Development tracking: [Development plan](DEVELOPMENT_PLAN.md), [Architecture](TECHNICAL_ARCHITECTURE.md), [Voice casting](VOICE_CASTING_SPEC.md).

## Implementation status

| Milestone | Status |
|---|---|
| M0 foundation | In progress |
| M1–M6 | Planned |

This decision was requested by the project owner on 2026-10-22.