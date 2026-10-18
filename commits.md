# Commit messages

Commit messages are in English. Use one type from this list, then a short description of why the change exists.

- `feat` — a new feature
- `fix` — a bug fix
- `chore` — maintenance that is not a user-facing fix or feature
- `refactor` — restructuring that does not fix a bug or add a feature
- `docs` — documentation only
- `style` — formatting that does not change behavior
- `test` — tests only
- `perf` — performance
- `ci` — continuous integration
- `build` — build system or external dependencies
- `revert` — revert a previous commit
- `security` — a vulnerability fix
- `hotfix` — an urgent production fix

Examples:

```text
feat: show startup volume fullness in the menu bar
fix: ask before the RAM room quits apps
docs: switch the README license notice to AGPL-3.0
```

Do not commit secrets, webhooks, bot tokens, SMTP passwords, or personal chat ids.

Version bumps use `chore: bump version to X.Y.Z` and happen only when a release is requested. See [CONTRIBUTING.md](CONTRIBUTING.md).
