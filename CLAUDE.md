# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

`PrettyMarkdown` — a native macOS SwiftUI + WebKit Markdown viewer, shipped as a
Swift Package. Swift sources live in `Sources/PrettyMarkdown/`, one type per
file. The entry point is `PrettyMarkdownApp.swift` (`@main`).

Key split: `MarkdownParser.swift` converts Markdown to body HTML (pure,
testable), and `MarkdownHTMLRenderer.swift` wraps it in the page template.

## Web assets are bundle resources

The viewer's CSS/JS and the sample document are real files in
`Sources/PrettyMarkdown/Resources/` (`theme.css`, `highlight.js`,
`scrollspy.js`, `Sample.md`) — edit them there, not as Swift strings. They are
declared as SwiftPM resources in `Package.swift` and loaded at runtime via
`Bundle.module`. `package.sh` copies the generated
`PrettyMarkdown_PrettyMarkdown.bundle` into the .app's `Contents/Resources`; if
that copy is missing the app crashes at first render with a "Missing bundled
resource" message.

Theme notes: `theme.css` holds the light/dark palettes once. Forced appearance
is applied by setting `data-theme="light|dark"` on `<html>`, and zoom by
setting `--font-scale` inline on `<html>` (see `MarkdownHTMLRenderer.render`).

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
