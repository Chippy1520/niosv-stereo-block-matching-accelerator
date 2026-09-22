# Project working agreement

## Scope and authoritative artifacts
- SystemVerilog stereo SAD accelerator on DE2-115. Implement one verified stage at a time.
- Root is both the source project and Obsidian vault. Preserve meaningful links and existing planning reports.
- `rtl/column_sum_buffer.sv` is the source of truth; the walkthrough embeds an exact snapshot.
- Do not claim unimplemented Nios V integration, fitted timing, 32-lane throughput or board success.

## User-authorized milestone publishing
The user requested ongoing GitHub updates and authorized revamping the existing public repository `Chippy1520/niosv-stereo-block-matching-accelerator`.

For completed changes made as part of assisted project work:
1. Inspect `git status` first. Do not overwrite or publish unrelated user work.
2. Update affected Obsidian notes, README status and `docs/progress.md` accurately. Keep source snapshots and line explanations synchronized when RTL changes.
3. Run `python scripts/check_walkthrough.py` and `python scripts/run_tests.py`. For synthesizable RTL/project changes, also run available Quartus Analysis & Synthesis and state what was or was not verified.
4. Review the exact staged diff and file list. Never stage credentials, `.env`, private notes, local tool binaries, datasets, build output, or workspace state.
5. Commit a coherent verified milestone and push to the existing origin using ordinary Git. Never force-push or rewrite history. If remote changes conflict, stop and resolve safely rather than overwriting them.
6. Check GitHub Actions and report the real outcome and commit/repository link. If tests fail or progress is incomplete, do not label the milestone verified.

This agreement is a workflow for active assisted work, not a background daemon. Manual edits are not automatically committed. A current explicit user request not to publish overrides the default.
