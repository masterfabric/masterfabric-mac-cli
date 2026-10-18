# Security Policy

## Security overview

MasterFabric Mac CLI is experimental local software. Sensors and `config.toml` stay on the Mac. We appreciate responsible disclosure.

## Supported versions

| Version | Supported |
| ------- | --------- |
| 0.4.x   | Yes |
| < 0.4   | No |

## Reporting a vulnerability

Do **not** open a public issue for a security vulnerability.

Email `license@masterfabric.co` with subject `[SECURITY] masterfabric-mac-cli`.

Include:

- What is affected (`mf`, menu bar, MCP, fan helper, or install)
- Steps to reproduce
- Impact
- A suggested fix, if you have one
- How to reach you

Do not include live webhooks, bot tokens, SMTP passwords, or personal chat ids. Describe the bug without the secret.

### Response

- Initial reply within 48 hours
- Assessment update within 7 days
- Fixes are prioritized and shipped in a release when confirmed

Researchers may be credited in the advisory unless they prefer to stay anonymous.

## What to expect in this project

- No telemetry. MCP is local stdio only.
- Integration credentials belong in `~/.config/masterfabric/config.toml`, which is not part of the repo.
- Fan control can install a privileged helper. Changes there need a clear consent path.
- Unsigned local builds can be killed by macOS; the installer ad-hoc signs binaries. That is not a security boundary.

## What not to report

- Issues already acknowledged
- Theoretical bugs without a way to reproduce them
- Social engineering or physical attacks
- Vulnerabilities that exist only in an unrelated third-party tool
- Missing secrets in example config (examples must stay placeholders)

## Legal

Security fixes and contributions are licensed under [GNU AGPL-3.0](LICENSE), the same license as [OSMEA](https://github.com/masterfabric-mobile/osmea) and [masterfabric_core](https://github.com/masterfabric-mobile/masterfabric_core).

**Owner:** MASTERFABRIC Bilişim Teknoloji A.Ş. (MASTERFABRIC Information Technologies Inc.)
**Website:** https://masterfabric.co
**Maintainer:** Gürkan Fikret Günak (@gurkanfikretgunak)

Emergency mail uses the same address with subject `[URGENT SECURITY] masterfabric-mac-cli`.
