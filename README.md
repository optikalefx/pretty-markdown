# Pretty Markdown

A native macOS Markdown **viewer** for reading local `.md` files with clean,
book-like typography. Built with SwiftUI and rendered through WebKit, it packages
its own lightweight Markdown parser and stylesheet — no external Markdown engine,
no editing, just a fast, focused reading experience.

Repository: <https://github.com/optikalefx/pretty-markdown>

## Download

Grab the latest signed `.app` from the
[Releases page](https://github.com/optikalefx/pretty-markdown/releases/latest):
download `PrettyMarkdown-*.zip`, unzip it, and move `PrettyMarkdown.app` to your
Applications folder.

The app is ad-hoc signed (not notarized), so on first launch right-click it and
choose **Open**, then confirm. Prefer to build it yourself? See
[Building & packaging](#building--packaging).

## Features

- **Open files any way you like** — the toolbar button, **⌘O**, the **Open
  Recent** menu (remembers your last 10 documents), drag-and-drop a `.md` file
  onto the window, or open one from Finder with Pretty Markdown as the handler.
- **Live reload** — the current file is watched and re-rendered automatically
  within a second of changing on disk, so it stays in sync with your editor.
- **Auto-generated table of contents** — headings become a sticky sidebar with
  **scroll-spy** highlighting that tracks your position; the sidebar disappears
  for documents without headings.
- **Light / dark / system appearance** — cycle with the toolbar button; the
  choice is remembered between launches.
- **Adjustable reading size** — zoom the text with **⌘+**, **⌘-**, and **⌘0**
  (reset). The scale is clamped to a comfortable range and persists.
- **Syntax highlighting** for fenced code blocks, with language auto-detection
  when no language is tagged (Swift, JavaScript, TypeScript, Python, Go, SQL,
  and Bash).
- **Warm, typographic theme** — Merriweather Sans, a subtle grid-paper canvas,
  and a "document on a page" layout that reads comfortably at any width.

### Supported Markdown

Headings, paragraphs, **bold** / *italic*, inline `code`, links, ordered and
unordered lists, task lists (`- [ ]` / `- [x]`), blockquotes, fenced code
blocks, tables, and horizontal rules.

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode command line tools)

## Building & packaging

Do **not** hand-assemble the `.app` bundle. Everything needed to produce a
signed app lives in `Packaging/`, and `package.sh` builds it from scratch:

```sh
./package.sh            # release build (default)
./package.sh debug      # debug build
```

The script:

1. Compiles the executable with `swift build`.
2. Assembles `outputs/PrettyMarkdown.app` (MacOS binary, Info.plist, PkgInfo).
3. Generates `AppIcon.icns` from `Packaging/AppIcon.png` and installs it into
   `Contents/Resources/`.
4. Ad-hoc code-signs the bundle and registers it with LaunchServices.

Run it directly for development:

```sh
swift run
```

## Changing the app icon

1. Replace `Packaging/AppIcon.png` with the new artwork (square PNG, ideally
   1024×1024).
2. Re-run `./package.sh`.

The icon keys (`CFBundleIconFile` / `CFBundleIconName`, both `AppIcon`) are
already set in `Packaging/Info.plist`, so no other changes are needed. If the
old icon lingers in Finder/Dock, that's just the icon cache — move the app to a
new folder or log out/in to refresh it.

## Layout

```
Sources/PrettyMarkdown/             App source (SwiftUI + WebKit), one type per file
Sources/PrettyMarkdown/Resources/   Web assets (theme.css, highlight.js, scrollspy.js, Sample.md)
Packaging/AppIcon.png               Source app-icon artwork (1024×1024)
Packaging/Info.plist                Info.plist template for the bundle
package.sh                          Build + assemble the signed .app
outputs/PrettyMarkdown.app          Generated bundle (do not edit by hand)
```
