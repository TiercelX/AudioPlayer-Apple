# Bug and status tracking

This directory holds current, problem-specific investigation state. Keep durable
workflow rules in `AGENTS.md` and `docs/dev/*.md`; keep temporary status,
evidence limits, next steps, and dated notes here.

## Current trackers

| File | Scope |
| --- | --- |
| `playback-core-phase1.md` | Apple-native playback core rewrite phase 1 status and validation gaps. |
| `playback-core-smoke.md` | Phase 1.1 ordinary media smoke evidence, manual/audible gaps, and local sample status. |
| `handoff-opencode-0604.md` | 2026-06-04 opencode handoff snapshot (archived). |

## Current known state

- **FFmpeg audio-core**: Self-built universal library (arm64 + x86_64) at
  version n8.1.1. Working for TrueHD decoding via FFmpegDecoder + FFmpegWrapper
  C bridge.
- **Pipeline integration**: Phase 1 ordinary playback now uses
  `PlaybackCoordinator` with native AVPlayer and PCM AVAudioEngine backends.
  Downmix, artifact monitor, seek cache, volume fade, and FFmpeg decoder files
  remain in the tree but are not connected to the ordinary Phase 1 playback
  path.
- **Tests**: Unit test framework in place; tests include generated WAV coverage
  and an optional local-media smoke evidence entry point.
- **Known critical bugs**: None currently.

## Ownership rules

- Keep each status file scoped to its problem domain.
- If evidence crosses domains, link the related status file and state which
  layer owns the next local change.
- Put durable rules in `docs/dev/*.md`; put temporary investigation state here.
- Prefer creating a new status file when a topic has its own evidence,
  validation path, and likely file ownership.

## Automatic landing

All local implementation agents should update these trackers as part of the same
completed work that changes current project state. The user should not need to
ask separately.

Update the narrowest matching tracker when a task:

- changes behavior or user-visible workflow;
- fixes, reproduces, rejects, or narrows a bug;
- changes diagnostics, harness reports, evidence bundles, scripts, or acceptance
  criteria;
- runs meaningful validation that changes current confidence;
- discovers a new limitation, evidence gap, ownership boundary, or next priority.

If no existing tracker fits, add a new status file and link it in the table
above. If a task does not update status tracking, the final response should say
why.

Status notes must remain evidence-honest:

- local build, smoke, test, commit, and push claims require local evidence from
  the agent making the claim;
- advisory-only output can propose wording, but cannot by itself establish
  validation status;
- clean internal PCM does not prove physical endpoint audio is pop-free.

## Status file shape

Use this shape for new trackers and for refreshing existing ones:

```markdown
# <Problem domain> status

This file tracks <scope>. Keep durable rules in `AGENTS.md` and `docs/dev/*.md`.

## Status refresh: YYYY-MM-DD

- Current known state.
- Evidence limits.
- What this file is not tracking.

## Current focus

- The next narrow diagnostic, implementation, or validation goal.

## Current priority order

1. First priority.
2. Second priority.

## Current validation baseline

- Commands or evidence needed before claiming a result.
- Known limitations of the evidence layer.

## Current acceptance bar

- What success means for this problem domain.

## Dated notes

- YYYY-MM-DD: Short note, evidence path, validation result, and remaining risk.
```

Keep the current sections near the top authoritative. Older dated notes are
history and should not override newer `docs/dev` rules or a newer status refresh.
