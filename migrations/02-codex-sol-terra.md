# Migration 02 — Claude Code scaffold to Codex Sol/Terra

Apply this at a task boundary. Finish or park every `.agents/T-*.md` whose
Status is not `done` before changing role definitions or the lead workflow.

## What changed

- `.claude/agents/{planner,senior-dev}.md` became native project-scoped
  Codex agents under `.codex/agents/*.toml`.
- `.claude/commands/{feature,toolkit-update}.md` became repository skills at
  `.agents/skills/{feature,toolkit-update}/SKILL.md`.
- `.codex/config.toml` pins the project lead to Sol and enables subagents.
- Sol (`gpt-5.6-sol`) now runs the lead, planner, and reviewer fallback.
- Terra (`gpt-5.6-terra`) runs the optional Codex implementer.
- `--claude-model` and `--reviewer-fallback-model` were removed. Use
  `--codex-sol-model` and `--codex-terra-model` only when overriding the
  defaults.

## Apply

1. Pull the updated toolkit checkout.
2. Run `bin/init.sh --update --target <project>` and review the new Codex
   destinations. An older provenance stamp supplies the existing project,
   builder, reviewer, tester, and test-directory values; Sol/Terra use their
   documented defaults when those new stamp keys are absent.
3. Run the same command without `--update` to add the missing Codex agent
   and skill files. Existing files are never overwritten.
4. Port any local behavioral customizations from the old `.claude` files
   into the matching Codex TOML `developer_instructions` or skill body.
   Do not copy Claude frontmatter into TOML.
5. Remove the old `.claude/` files only after verifying the Codex files are
   discovered and the local customizations are present.
6. Run `scripts/verify-spec.sh` and `scripts/verify-state.sh` against a
   representative task, then run one small `$feature` task end to end.
7. Refresh the baseline with
   `bin/init.sh --refresh-stamp --target <project>`.
