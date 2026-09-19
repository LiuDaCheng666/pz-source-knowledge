---
name: pz-vanilla-source-research
description: Build, query, validate, and cite locally generated vanilla Project Zomboid source evidence for Mod compatibility and API questions. Use when verifying shipped Lua, scripts, Java bytecode APIs, reconstructed Java behavior, events, protocols, or changes between game Builds.
---

# Project Zomboid Vanilla Source Research

Use the knowledge base as a read-only source of vanilla game evidence. Keep all
Mod source, dependency analysis, compatibility reports, and release data in the
consuming Mod's repository.

## Locate The Knowledge Base

Prefer `PZ_SOURCE_KNOWLEDGE_ROOT` when it is set. Otherwise locate a checkout
containing `Search-PZSourceKnowledge.ps1`, `Validate-PZSourceKnowledge.ps1`, and
`current.json`. Do not assume a machine-specific drive or user directory.

If `current.json` is absent, the local snapshot has not been built. Building it
requires the user's own Project Zomboid Dedicated Server installation and CFR
JAR; follow the repository README instead of downloading or redistributing game
files.

## Evidence Workflow

1. Read `current.json`; record `gameBuildId`, `gameSnapshotId`, and
   `jarSha256` in any compatibility conclusion.
2. Search before inferring behavior:

   ```powershell
   pwsh -NoProfile -File .\Search-PZSourceKnowledge.ps1 `
     -Query '<API, event, class, or behavior>' -Scope game -Limit 20
   ```

3. Open the smallest relevant files from the active snapshot and cite their
   snapshot-relative paths and lines.
4. Use this evidence order:
   - shipped vanilla Lua and scripts for exact Lua/script behavior;
   - `javap` signatures and JVM descriptors for authoritative Java API shape;
   - CFR output for reconstructed implementation details;
   - names or behavior remembered from older Builds only as search leads.
5. When evidence is ambiguous, search callers, event registration, both
   client/server paths, and the relevant network direction before concluding.
6. Validate the knowledge base before a compatibility or release decision:

   ```powershell
   pwsh -NoProfile -File .\Validate-PZSourceKnowledge.ps1
   ```

## Game Updates

Use `Check-PZSourceKnowledgeUpdate.ps1 -SourceRoot <candidate-server>` against
an isolated candidate installation. It compares the Build ID, JAR, Lua/scripts
tree, and text metadata hashes. Build a new immutable snapshot when any input
changes; do not overwrite an older snapshot or manually edit generated data.

Compare the generated report for removed or changed Java APIs, Lua symbols,
events, protocols, and files. Compatibility impact remains the responsibility
of each consuming Mod and must be recorded there.

## Boundaries

- Never add Mod files, Workshop IDs, server paths, player data, credentials, or
  Mod-specific indexes to the vanilla knowledge repository.
- Never publish `generated/`, `current.json`, the game JAR, shipped game files,
  or decompiled Java.
- Do not claim CFR output is official source.
- Do not claim runtime compatibility from static source evidence alone; run the
  consuming Mod's own tests against the same game Build.
