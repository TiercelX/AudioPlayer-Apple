# Agent workflow

Use this page for collaboration and change-scope rules. Use
`docs/bug/README.md` as the status-tracking index. Use `docs/dev/code-map.md`
for first-pass file navigation before opening large source files.

## Collaboration

- This is a native macOS application built with Swift + SwiftUI + AVFoundation.
- Make minimal, localized changes and keep the existing project structure.
- Explain the plan before editing code.
- Keep plan and progress explanations brief unless the user asks for more detail.
- Prefer SwiftUI and AVFoundation APIs over AppKit where possible.
- Do not rename files or classes unless required.
- Read and edit the smallest relevant set of files needed for the task.
- When adding features, describe which files changed.

## Scope

- Documentation-only tasks must not modify Swift source files, Xcode project
  files, or scripts unless the user explicitly expands the scope.
- Preserve existing behavior unless the task explicitly asks for a behavior
  change.
- Preserve the dual-thread model: decoder thread + audio output thread.
- Preserve teardown order: release audio output, stop decoder, clear buffer.

## Audio architecture rules

- Preserve AVFoundation as primary decoder for supported formats (EAC3/AC3,
  AAC, FLAC, WAV, MP3).
- Use FFmpeg libav for TrueHD and complex formats.
- Route format detection through DecoderRouter before selecting decoder path.
- Preserve AVAudioEngine as output layer.
- Let system handle spatial audio rendering for AirPods head tracking.
- Preserve Dolby LoRo/LtRt matrix downmix coefficients.

## opencode local-agent mode

- Use opencode with Xiaomi MiMo as a local implementation agent when it can
  read and edit files, run local commands, inspect logs, and manage git state.
- Treat opencode output as advisory only when it cannot execute local commands.
- **Branch isolation**: opencode branches should identify both executor and
  model, such as `opencode-MiMo-*`. Never operate on each other's branches.
- Use a separate `git worktree`, a unique task-specific branch, and
  non-overlapping file ownership for each active opencode task.
- opencode may claim local validation only from actual local execution or local
  artifact inspection in its assigned worktree.

## Analysis, validation, and commits

- Analysis-only tasks do not require commits or pushes.
- Commit only completed implementation work after relevant validation passes.
- Do not commit partial, exploratory, or failing intermediate states.
- Keep each commit scoped to one completed task or one clearly separable subtask.

## Validation requirements

- Build must succeed with `xcodebuild -scheme AudioPlayerMac -configuration
  Debug`.
- Smoke test must pass with test EAC3, TrueHD, FLAC, MP3 files.
- No memory leaks detected by Instruments.
- Smoke tests must report PASS, FAIL, or INCONCLUSIVE.

## Status landing protocol

Agents should update status tracking as part of normal completion, not as a
separate user-driven chore.

Update the relevant `docs/bug/*-status.md` tracker when the task:

- adds, removes, or changes user-visible behavior;
- fixes, reproduces, rejects, or narrows a bug;
- changes diagnostics, reports, evidence bundles, scripts, or harness contracts;
- runs meaningful build, smoke, test, or validation that affects current
  confidence;
- discovers a new limitation, evidence gap, acceptance bar, or next priority.

When landing status:

- choose the narrowest matching tracker from `docs/bug/README.md`;
- add a dated note or refresh the current top sections when the new state should
  guide the next agent;
- include exact commands, report/log paths, result (`PASS`, `FAIL`, or
  `INCONCLUSIVE`), and evidence-layer limits when available;
- keep durable workflow rules in `docs/dev/*.md` instead of duplicating them in
  bug trackers.

If no existing tracker fits, add a new narrow tracker and link it from
`docs/bug/README.md`. If no status update is needed, the final response should
say why.

## Diagnostics honesty

- Do not guess fixes for audible pops/clicks without improving observability.
- Treat decoder-side PCM, internal levels, and actual output-device audio as
  different evidence layers.
- Clean internal PCM does not prove physical endpoint audio is pop-free.

## Mandatory completion protocol

Before finishing any task that changed files, run `git status` and classify
every changed or untracked path as one of:

1. intentional source/script/docs changes;
2. generated artifacts;
3. local-only files;
4. unknown.

Stage only intentional project changes. Do not stage build outputs, cache/logs,
or generated `.wav`/`.json`/`.raw`/report artifacts unless the user explicitly
asks to track one of those outputs.

Commit and push completed intentional changes to the current tracking branch
unless the user explicitly says not to. Use the repository's normal validation
expectations before committing; documentation-only edits may use a scoped
documentation review instead of a build.

If anything is left uncommitted, list the exact files or directories and explain
why each was left out. The final response for file-changing tasks must include:

- commit hash, if a commit was made;
- pushed branch, if a push was made;
- status tracker updated, or why no tracker update was needed;
- remaining modified or untracked files;
- why each remaining file was left uncommitted.
