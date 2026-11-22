# Changelog

All notable changes to Industry Pollution Display are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the mod uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
mod's `revision` in `mod.json` is MAJOR * 10000 + MINOR * 100 + PATCH.

## [Unreleased]

### Changed
- The mod's name in the game's mod list and on mod.io is now English only:
  "Industry Pollution Display" instead of the English and Japanese names
  together. The summary and description keep their Japanese and other
  languages, and the in-game texts are unchanged.

## [1.0.0] - 2026-11-18

### Added
- First public release (published with `revision` 1, before the mod was
  versioned). A card with the current noise and pollution in the windows of
  industries, depots and maintenance buildings, using the game's own noise
  and pollution card and rounding.
- Industries: the total of every emitting part of the industry's
  construction, so it changes with production and greenification; the card
  sits between the production rules and the boosters.
- Depots and maintenance buildings: the building's own emission, which
  follows its maintenance pool usage; the card sits under the maintenance
  pool.
- A building that emits nothing at all shows no card. Nothing is logged
  while the mod works; a failed read shows no card and logs one
  `[IPD] emission read failed: ...` line per distinct error.
- Texts in the game's 13 languages. GUI only: no save data is changed, no
  base file is replaced and there are no dependencies.
