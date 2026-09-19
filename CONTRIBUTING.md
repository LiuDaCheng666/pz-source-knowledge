# Contributing

Contributions to the extraction, indexing, validation, search, and documentation tooling are welcome.

Do not submit Project Zomboid game files, decompiled Java, shipped Lua/scripts, translations, assets, or excerpts containing substantial copyrighted game code.

Before opening a pull request:

1. Parse every PowerShell script with the PowerShell parser.
2. Run `node --check` on every `.mjs` file.
3. Build or reuse a local snapshot from a legally installed dedicated server.
4. Run `Validate-PZSourceKnowledge.ps1`.
5. Exercise at least one Lua, Java, event, and scripts search.
6. Confirm `generated/`, `.tools/`, and `current.json` are not tracked.

Changes must remain generic and vanilla-only. Integration logic for an individual Mod belongs in that Mod's repository.
