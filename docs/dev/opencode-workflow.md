# opencode workflow

Use this page when opencode is connected for local agent work.
opencode is treated according to what it can actually do in the local
workspace:

- If opencode can read and edit files, run commands, inspect logs and
  reports, and manage git state, it is a local implementation agent.
- If opencode only returns model text or remote advice without local
  execution, it is advisory only and cannot claim local validation.

## Role boundary

opencode is a local implementation agent when it has full access to the
worktree. When opencode is assigned work, give it a single focused task,
exact allowed files or directories, forbidden files, a dedicated branch,
and a dedicated build directory.

## Branch and worktree isolation

Use branch names that identify both the executor and the main model:

| Agent | Branch pattern | Example |
|-------|----------------|---------|
| opencode with Xiaomi MiMo | `opencode-MiMo-MMDD-task` | `opencode-MiMo-0604-apple-architecture` |
| opencode with another main model | `opencode-Model-MMDD-task` | `opencode-DeepSeek-0604-decoder-router` |

- Use a separate `git worktree` for each active opencode task.
- Do not run opencode against another agent's active working directory
  unless the task is read-only.
- Do not edit the same file from multiple agents in parallel.
- Use a task-specific build directory such as `build-opencode-decoder`.
- Commit and merge one completed branch at a time.

## Validation and claims

opencode may claim build, smoke-test, regression, log-inspection,
report, artifact, commit, and push results only when it actually
performed that local action or inspected the local artifact in its
assigned worktree.

It must not claim:

- local build or smoke-test success from model reasoning alone;
- physical endpoint audio quality from internal PCM or submitted PCM
  checks;
- audible pop/click fixes without endpoint-layer diagnostic evidence and
  the stated limitation of that evidence;
- branch, commit, push, tag, release, or pull-request state unless it
  performed or inspected that git action locally.

## Completion

opencode follows the same completion protocol as other local agents:

- inspect `git status` and classify every changed or untracked file;
- stage only intentional project changes;
- leave build outputs, logs, generated reports, and local-only files
  untracked unless the user explicitly asks to track them;
- update the relevant `docs/bug/*-status.md` tracker when the task
  changes behavior, diagnostics, harness contracts, validation
  confidence, or current investigation state;
- commit and push only completed validated work unless the user
  instructs otherwise.

## Handoff template

Use this when assigning work to opencode:

```text
You are opencode using Xiaomi MiMo as a local implementation agent for AudioPlayerMac.
Use branch <opencode-MiMo-MMDD-task>.
Do not edit files owned by another active agent.

Task:
<one focused implementation task>

Scope:
- Allowed files: <list exact files or directories>
- Do not touch FFmpeg integration unless explicitly listed.
- Do not touch UI files unless explicitly listed.

Required context:
- AGENTS.md
- docs/dev/architecture.md
- docs/dev/decoder-paths.md
- docs/dev/ffmpeg-integration.md

Validation:
- Build: xcodebuild -scheme AudioPlayerMac -configuration Debug build
- Test with sample files
- Verify functionality works as expected

Completion:
- Report changed files
- Report exact commands and results
- Commit and push the branch
```

## Example tasks

### Task 1: Implement AVFoundationDecoder

```text
You are opencode using Xiaomi MiMo as a local implementation agent for AudioPlayerMac.
Use branch opencode-MiMo-0605-avfoundation-decoder.

Task:
Implement AVFoundationDecoder and AudioFormatDetector.

Scope:
- Allowed files:
  - AudioPlayerMac/Decoders/AVFoundation/AVFoundationDecoder.swift
  - AudioPlayerMac/Decoders/Common/AudioFormatDetector.swift
  - AudioPlayerMac/Decoders/Common/AudioDecoder.swift
- Do not touch FFmpeg integration.
- Do not touch UI files.

Required context:
- AGENTS.md
- docs/dev/architecture.md
- docs/dev/decoder-paths.md

Validation:
- Build: xcodebuild -scheme AudioPlayerMac -configuration Debug build
- Test with FLAC, MP3, WAV files
- Verify decode() returns valid AVAudioPCMBuffer
- Verify seek() works correctly

Completion:
- Report changed files
- Report exact commands and results
- Commit and push the branch
```

### Task 2: Implement FFmpegDecoder

```text
You are opencode using Xiaomi MiMo as a local implementation agent for AudioPlayerMac.
Use branch opencode-MiMo-0606-ffmpeg-decoder.

Task:
Implement FFmpegDecoder, FFmpegWrapper, and FFmpegBridge.

Scope:
- Allowed files:
  - AudioPlayerMac/Decoders/FFmpeg/FFmpegDecoder.swift
  - AudioPlayerMac/Decoders/FFmpeg/FFmpegWrapper.swift
  - AudioPlayerMac/Decoders/FFmpeg/FFmpegBridge.h
  - AudioPlayerMac/Decoders/FFmpeg/FFmpegBridge.c
- Do not touch AVFoundation decoder.
- Do not touch UI files.

Required context:
- AGENTS.md
- docs/dev/architecture.md
- docs/dev/ffmpeg-integration.md

Validation:
- Build: xcodebuild -scheme AudioPlayerMac -configuration Debug build
- Test with TrueHD file
- Verify decode() returns valid AVAudioPCMBuffer
- Verify seek() works correctly

Completion:
- Report changed files
- Report exact commands and results
- Commit and push the branch
```

### Task 3: Implement UI

```text
You are opencode using Xiaomi MiMo as a local implementation agent for AudioPlayerMac.
Use branch opencode-MiMo-0607-ui.

Task:
Implement MainWindow and PlayerControlsView.

Scope:
- Allowed files:
  - AudioPlayerMac/UI/MainWindow.swift
  - AudioPlayerMac/UI/PlayerControlsView.swift
  - AudioPlayerMac/App/AppState.swift
- Do not touch decoder files.
- Do not touch audio engine files.

Required context:
- AGENTS.md
- docs/dev/architecture.md
- docs/dev/phase1-tasks.md

Validation:
- Build: xcodebuild -scheme AudioPlayerMac -configuration Debug build
- Verify UI displays correctly
- Verify buttons work (play/pause/stop)
- Verify progress slider works

Completion:
- Report changed files
- Report exact commands and results
- Commit and push the branch
```

## Multi-agent coordination

When multiple agents work on the same project:

1. **Task decomposition**: Split work into independent tasks
2. **File ownership**: Each agent owns specific files
3. **Branch isolation**: Each agent works on its own branch
4. **Communication**: Agents report completion to master
5. **Integration**: Master merges completed branches

### Example multi-agent workflow

```
Master agent (opencode-MiMo)
├── Task 1: AVFoundationDecoder (opencode-MiMo-0605)
├── Task 2: FFmpegDecoder (opencode-MiMo-0606)
├── Task 3: UI (opencode-MiMo-0607)
└── Task 4: Integration (after all tasks complete)
```

## Error handling

If opencode encounters an error:

1. **Build error**: Report error, suggest fix
2. **Test failure**: Report failure, suggest investigation
3. **Git error**: Report error, suggest resolution
4. **File conflict**: Stop, report conflict, wait for resolution

## Best practices

1. **Single responsibility**: Each task should be focused
2. **Clear scope**: Define allowed and forbidden files
3. **Validation first**: Always validate before committing
4. **Documentation**: Update docs when behavior changes
5. **Communication**: Report completion clearly

## Troubleshooting

### Build fails
- Check error message
- Verify file paths
- Check imports
- Clean build folder

### Tests fail
- Check test output
- Verify expected behavior
- Debug with breakpoints
- Check edge cases

### Git conflicts
- Stash changes
- Pull latest
- Resolve conflicts
- Commit resolution
