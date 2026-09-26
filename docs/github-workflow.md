# GitHub updates

Repository: https://github.com/Chippy1520/niosv-stereo-block-matching-accelerator

Visibility: **public**, matching the existing repository. Original history and feasibility documents are preserved.

## During assisted development

Completed project milestones are documented, verified, committed and pushed as part of the work. `AGENTS.md` carries this agreement for future coding sessions. The assistant reviews staged files and protects unrelated local work. No credentials, generated databases, machine-specific workspace files or bundled simulator binaries belong in commits.

## What is automatic

Every push or pull request triggers `.github/workflows/rtl-tests.yml`:
1. Install Icarus Verilog on an Ubuntu runner.
2. Check the walkthrough's embedded RTL matches the source.
3. Run 38 standalone/integrated simulation cases, including the row-buffer suite and the preserved Python-reference buffer cases.
4. Verify five deliberately faulty RTL copies are rejected by the benches.
5. Upload simulation results and test artifacts.

## What is not automatic

No unattended file watcher or scheduled job commits files. Manual edits are not uploaded until a commit and push. CI verifies code already pushed; it does not sync a local Desktop folder. Quartus synthesis/fitting and FPGA hardware tests are not run in cloud CI.

## Manual update

```sh
python scripts/check_walkthrough.py
python scripts/run_tests.py
python scripts/check_test_sensitivity.py
git status --short
git diff
# Stage only the intended project files, then review:
git diff --cached
git commit -m "Describe the verified milestone"
git push origin main
```

See [progress](progress.md) for milestone evidence, and the repository Actions tab for CI status.
