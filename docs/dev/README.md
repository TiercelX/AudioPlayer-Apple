# Developer documentation index

This directory holds durable workflow, architecture, and validation docs for
AudioPlayerMac. Temporary investigation state lives in `docs/bug/` instead.

## Entry points (start here)

| File | Purpose | When to read |
| --- | --- | --- |
| `agent-workflow.md` | Collaboration rules, scope limits, status landing protocol | First file for any agent session |
| `code-map.md` | File-by-file navigation map and playback pipeline data flow | Before opening large source files |
| `build-guide.md` | Prerequisites, FFmpeg setup, build commands, testing, troubleshooting | Before building or running tests |
| `quick-reference.md` | One-page cheat sheet for common commands and key file locations | Quick lookup during work |

## Validation and diagnostics

| File | Purpose | When to read |
| --- | --- | --- |
| `validation.md` | Validation checklist, smoke test formats, report schema, acceptance criteria | Before running smoke tests or writing validation code |
| `artifact-monitor.md` | Audio artifact detection design (pops, clicks, silence gaps) | When working on `AudioArtifactMonitor` |

## Audio architecture

| File | Purpose | When to read |
| --- | --- | --- |
| `architecture.md` | High-level architecture overview | When understanding the overall system design |
| `decoder-paths.md` | AVFoundation vs FFmpeg decoder path selection rules | When modifying `DecoderRouter` or adding decoder support |
| `dolby-downmix.md` | LoRo/LtRt matrix downmix coefficients and processing | When working on `DolbyDownmixProcessor` |
| `ffmpeg-integration.md` | FFmpeg libav C bridge setup and integration | When working on FFmpeg decoder files |
| `output-format.md` | Audio output format negotiation and configuration | When modifying output format handling |
| `pcm-seek-cache.md` | PCM seek cache design and eviction strategy | When working on `PcmSeekCache` |
| `spatial-audio.md` | Spatial audio and AirPods head tracking support | When working on spatial audio features |

## Task planning

| File | Purpose | When to read |
| --- | --- | --- |
| `phase1-tasks.md` | Detailed Phase 1 MVP task breakdown and implementation guide | When planning or executing Phase 1 work |

## Agent coordination

| File | Purpose | When to read |
| --- | --- | --- |
| `opencode-workflow.md` | opencode local-agent role, branch isolation, handoff templates | When assigning work to opencode |

## Non-durable files

No non-durable files currently in this directory.
The `handoff-opencode-0604.md` snapshot has been moved to `docs/bug/handoff-opencode-0604.md`.

## Reading order for new agents

1. `agent-workflow.md` — collaboration and scope rules
2. This file (`README.md`) — find the right doc for your task
3. `code-map.md` — locate relevant source files
4. The specific doc matching your task from the tables above
5. `docs/bug/README.md` — current status and known issues
