# Contributing to MasterFabric Mac CLI

Thanks for helping. This repository is the macOS CLI, menu bar, and local MCP server. It follows the same open-source process as [OSMEA](https://github.com/masterfabric-mobile/osmea) and [masterfabric_core](https://github.com/masterfabric-mobile/masterfabric_core): AGPL-3.0, a code of conduct, and private security reports.

Contributions are licensed under [GNU AGPL-3.0](LICENSE).

## Ways to help

- Bug reports and feature requests via the issue templates
- Documentation in `README.md` and `examples/`
- CLI, menu bar, or MCP changes in Swift
- Security reports by email, not in a public issue — see [SECURITY.md](SECURITY.md)

## Setup

Requirements: macOS 13+, Swift 5.9+ (Xcode or the Command Line Tools). Apple Silicon is the primary target.

```bash
git clone https://github.com/masterfabric/masterfabric-mac-cli.git
cd masterfabric-mac-cli
make install
export PATH="$HOME/.local/bin:$PATH"
mf version
mf status
```

Layout:

```text
Sources/MasterFabricCore/     shared metrics, config, version
Sources/mf/                   CLI and MCP stdio server
Sources/MasterFabricMenuBar/  menu bar app
scripts/install.sh            installer
Formula/masterfabric.rb       Homebrew formula
VERSION                       semver source of truth
```

User config stays in `~/.config/masterfabric/config.toml`. Do not commit that file.

## Workflow

1. Branch from `main`: `feat/…`, `fix/…`, or `docs/…`.
2. Keep logic in `MasterFabricCore`. The CLI and menu bar stay thin.
3. Commit in English using [commits.md](commits.md).
4. Open a pull request with [pull_request_template.md](pull_request_template.md). Title and body in English.
5. Do not bump `VERSION` or tag a release unless a maintainer asked for that release.

```bash
swift build -c release --product mf
swift build -c release --product MasterFabricMenuBar
```

On a machine without Xcode.app, SwiftUI `@State` macros can fail. Use `@StateObject` for local form state. See `.cursor/rules/menubar-swiftui.mdc`.

## Review

Maintainers review for privacy (no secrets, no telemetry), fan-helper consent, and a stable MCP tool list. Additive JSON fields are preferred over renames.

## Conduct

[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Enforcement contact: info@masterfabric.co.
