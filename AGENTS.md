# Codex Usage Alert development rules

These rules apply to every change in this repository.

## Required development log

Every completed development task must update `DEVELOPMENT_LOG.md` before it is
considered complete. Add the newest entry at the top of the current section and
use the local time in Asia/Shanghai.

Each entry must include:

- completion time in `YYYY-MM-DD HH:mm:ss CST (UTC+08:00)` format;
- app version and build number from `Resources/Info.plist`;
- a concise description of the user-visible result;
- the principal files or components changed;
- verification performed and its result;
- the branch and commit, or `pending commit` when the log is committed together
  with the implementation.

Use this command to obtain a consistent timestamp:

```sh
TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S CST (UTC+08:00)'
```

Do not record unfinished or uncommitted work as completed. When several agents
or worktrees are active, preserve their entries and keep entries in reverse
chronological order.

## Version and release notes

- Treat `Resources/Info.plist` as the source of truth for the marketing version
  (`CFBundleShortVersionString`) and build number (`CFBundleVersion`).
- Follow the repository-specific decimal mapping in `docs/versioning.md`:
  every committed modification increments the Build, and the marketing version
  is derived from that Build (`1` → `0.0.1`, `21` → `0.2.1`, `100` → `1.0.0`).
- Run `scripts/sync_version.sh` before packaging or committing a completed
  change so the pending commit receives its final version and Build.
- Record the effective version and build number in every development-log entry,
  even for documentation and maintenance changes.
- Update `CHANGELOG.md` for every user-facing release. Keep implementation
  details and per-task verification in `DEVELOPMENT_LOG.md`; keep release notes
  concise and user focused.

## Completion checklist

Before reporting a task as complete:

1. Run checks appropriate to the change.
2. Confirm the effective app version and build number.
3. Update `DEVELOPMENT_LOG.md` with the completion timestamp and results.
4. Update `CHANGELOG.md` when the task produces a user-facing release.
5. Review the diff so unrelated work is not included.
6. Commit only the intended files and report the commit identifier.
