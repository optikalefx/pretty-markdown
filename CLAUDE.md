# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

`PrettyMarkdown` — a native macOS SwiftUI + WebKit Markdown viewer, shipped as a
Swift Package. All app code is in `Sources/PrettyMarkdown/main.swift`.

## Build & run

- `swift run` — run during development.
- `swift build -c release` — compile only.
- `./package.sh [debug|release]` — build **and** assemble the signed `.app`.

## The .app bundle is generated — never hand-assemble it

`outputs/PrettyMarkdown.app` is a build artifact. Do not edit files inside it
directly (icon, Info.plist, signature); those edits are lost on the next
`package.sh` run. Instead change the source of truth in `Packaging/` and re-run
`./package.sh`:

- `Packaging/AppIcon.png` — source app-icon artwork (square, ~1024×1024).
- `Packaging/Info.plist` — the bundle's Info.plist template.

`package.sh` compiles the binary, assembles the bundle, regenerates
`AppIcon.icns` from `Packaging/AppIcon.png` (via `sips` + `iconutil`), ad-hoc
signs, and registers with LaunchServices.

## Changing the app icon

Replace `Packaging/AppIcon.png` and run `./package.sh`. The icon plist keys
(`CFBundleIconFile` / `CFBundleIconName`, both `AppIcon`) are already in
`Packaging/Info.plist`. A stale icon in Finder/Dock is just the icon cache, not
a build problem.
