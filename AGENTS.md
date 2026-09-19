# Project Zomboid Source Knowledge Rules

This repository is a vanilla-only, locally generated evidence base for Project Zomboid Mod development.

## Evidence workflow

1. Read `current.json` and record `gameBuildId`, `gameSnapshotId`, and `jarSha256`.
2. Query evidence with `Search-PZSourceKnowledge.ps1` before relying on a vanilla Lua or Java API.
3. Treat shipped Lua and scripts as exact source evidence.
4. Treat `javap` signatures and JVM descriptors as authoritative Java API evidence.
5. Treat CFR output as reconstructed implementation for reading, not official source.
6. Cite the snapshot ID, path, and relevant line when documenting a compatibility decision.

Example:

```powershell
pwsh -NoProfile -File .\Search-PZSourceKnowledge.ps1 `
  -Query 'NetworkCharacterAI resetSpeedLimiter' -Scope game -Limit 20
```

## Repository boundary

- Never add any Mod source, Mod identifier, Workshop metadata, dependency overlay, or Mod-specific report to this repository.
- Keep generated game files under `generated/`; they must never be committed or published.
- A consuming Mod may read this knowledge base, but all Mod-specific analysis must remain in that Mod's repository.
- Do not infer that an API from an older Build exists in the active Build. Verify it against `current.json`.
