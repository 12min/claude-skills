---
name: youtube-content
description: "YouTube transcripts to summaries, threads, blogs."
platforms: [linux, macos, windows]
---

# YouTube Content Tool

## When to use

Use when the user shares a YouTube URL or video link, asks to summarize a video, requests a transcript, or wants to extract and reformat content from any YouTube video. Transforms transcripts into structured content (chapters, summaries, threads, blog posts).

Extract transcripts from YouTube videos and convert them into useful formats.

## Setup

Prefer `uv run --with youtube-transcript-api ...` for one-off transcript fetches. This avoids requiring an active virtualenv and installs the dependency into an ephemeral uv environment for the command:

```bash
uv run --with youtube-transcript-api python3 SKILL_DIR/scripts/fetch_transcript.py "URL" --timestamps
```
## Setup

Prefer per-command dependency injection so the helper works even when the current
project has no active virtualenv:

```bash
uv run --with youtube-transcript-api python3 SKILL_DIR/scripts/fetch_transcript.py "URL" --timestamps
```

If you intentionally want to install the dependency into an existing active venv,
you can still run:

```bash
uv pip install youtube-transcript-api
```

Pitfall: `uv pip install youtube-transcript-api` fails with “No virtual environment found” in repos without an active venv. In that case do not create a project venv just for this task; use `uv run --with youtube-transcript-api ...` instead.

## Helper Script

`SKILL_DIR` is the directory containing this SKILL.md file. The script accepts any standard YouTube URL format, short links (youtu.be), shorts, embeds, live links, or a raw 11-character video ID.

```bash
# JSON output with metadata
uv run --with youtube-transcript-api python3 SKILL_DIR/scripts/fetch_transcript.py "https://youtube.com/watch?v=VIDEO_ID"

# Plain text (good for piping into further processing)
uv run --with youtube-transcript-api python3 SKILL_DIR/scripts/fetch_transcript.py "URL" --text-only

# With timestamps
uv run --with youtube-transcript-api python3 SKILL_DIR/scripts/fetch_transcript.py "URL" --timestamps

# Specific language with fallback chain
uv run --with youtube-transcript-api python3 SKILL_DIR/scripts/fetch_transcript.py "URL" --language tr,en
```

## Default behavior

When a user shares a YouTube URL without specifying another output and an Obsidian vault is available, save the processed summary to Obsidian by default instead of only replying in chat. Use the vault resolved by the `obsidian` skill and create/update notes under:

`Knowledge/Sources/Videos/<sanitized title>.md`

Still return a concise chat confirmation with the created note path and 3-5 bullet highlights. Do not ask whether to save unless the user explicitly asks for chat-only output, transcript-only output, or another destination.

For SaaS / marketing / microSaaS videos, bias the note toward roadmap synthesis and practical product/growth decisions. Add practical sections that help roadmap synthesis, such as:

- `Aplicação para roadmap de SaaS`
- `Hipóteses para testar`
- `Checklist acionável`
- `Riscos / críticas`
- `Conexões com marketing, aquisição, produto, pricing, onboarding, retenção ou viralidade`

Use topics like `SaaS`, `microSaaS`, `marketing`, `growth`, `aquisição`, `produto`, `roadmap` when appropriate. Keep `processed: false` and `concepts_extracted: []` so later workflows can synthesize these notes into a roadmap.

For the detailed note shape and extraction bias for SaaS-roadmap study workflows, see `references/saas-roadmap-video-notes.md`.

## Output Formats

After fetching the transcript, save an Obsidian note by default when a vault is available, or format it based on what the user asks for:

- **Obsidian source note**: Default when saving to Obsidian — frontmatter + summary + key points + roadmap implications + actionable checklist + critical notes
- **Chapters**: Group by topic shifts, output timestamped chapter list
- **Summary**: Concise 5-10 sentence overview of the entire video
- **Chapter summaries**: Chapters with a short paragraph summary for each
- **Thread**: Twitter/X thread format — numbered posts, each under 280 chars
- **Blog post**: Full article with title, sections, and key takeaways
- **Quotes**: Notable quotes with timestamps

## Obsidian / durable-note pattern

When the user asks to save a YouTube summary to Obsidian, or says follow-ups like "agora faz para esse" after a prior video was saved to Obsidian, continue the same durable-note workflow without asking again:

1. Load/use the `obsidian` skill and resolve the concrete vault path from Obsidian config or the known vault path.
2. Fetch metadata with `yt-dlp --skip-download --print '%(title)s\n%(uploader)s\n%(duration_string)s\n%(upload_date)s' "URL"`.
3. Fetch transcript to `/tmp/<video_id>.transcript.json` with an explicit fallback chain for Portuguese/marketing videos: `--language pt,pt-orig,en --timestamps`.
4. Validate the transcript JSON is non-empty and inspect enough of it to summarize accurately. For ~30-40K character transcripts, grouping timestamped lines into 3-minute windows is a good low-noise inspection pattern.
5. Create a note under `Knowledge/Sources/Videos/<sanitized title>.md` when the vault uses the PARA/PKM convention. Use frontmatter `type: source/video`, `source`, `author`, `topics`, `concepts_extracted: []`, and `processed: false`. If the vault has a stricter frontmatter convention, include its required standard fields as well.
6. Include practical sections, not just prose: summary, main idea, key points, actionable checklist, and critical notes. For tool/setup videos, add "how to use" or "implications" sections as appropriate.
7. Verify by reading back the first lines of the created note before telling the user the path.

### Example — Chapters Output

```
00:00 Introduction — host opens with the problem statement
03:45 Background — prior work and why existing solutions fall short
12:20 Core method — walkthrough of the proposed approach
24:10 Results — benchmark comparisons and key takeaways
31:55 Q&A — audience questions on scalability and next steps
```

## Workflow

1. **Fetch** the transcript using the helper script with `--text-only --timestamps` via `uv run python3`.
   - For Portuguese/Brazilian marketing videos, prefer an explicit fallback chain first: `--language pt,pt-orig,en`. Some videos that fail with the default language lookup return a valid transcript with this chain.
   - For long transcripts or when you will need to transform/save the result elsewhere, redirect JSON output to `/tmp/<video_id>.transcript.json` and process that file rather than letting terminal output truncate the transcript.
2. **Fetch metadata** when creating durable notes or research artifacts: `yt-dlp --skip-download --print '%(title)s\n%(uploader)s\n%(duration_string)s\n%(upload_date)s' "URL"`. Use title, channel, duration, and upload date in the note frontmatter/body.
3. **Validate**: confirm the output is non-empty and in the expected language. If empty, retry without `--language` to get any available transcript, then retry common localized chains such as `pt,pt-orig,en` when relevant. If still empty, tell the user the video likely has transcripts disabled.
   - Helper JSON shape pitfall: `scripts/fetch_transcript.py --timestamps` writes `full_text` and `timestamped_text` plus `segment_count`/`duration`, not necessarily a `segments` array. Validate using `segment_count > 0` and/or non-empty `full_text`/`timestamped_text`; do not conclude transcript extraction failed just because a `segments` key is absent.
   - If transcript APIs/subtitle downloads are blocked but the video audio is downloadable, use the local transcription fallback in `references/local-transcription-fallback.md` rather than browser automation. Prefer writing timestamped output incrementally to `/tmp/<video_id>_transcribed*.txt`; if the transcription process times out, check whether the partial/complete output file exists before giving up.
4. **Chunk if needed**: if the transcript exceeds ~50K characters, split into overlapping chunks (~40K with 2K overlap) and summarize each chunk before merging. For ~30-40K transcripts, a useful inspection pattern is grouping timestamped lines into 3-minute windows before writing the final summary.
4. **Chunk if needed**: if the transcript exceeds ~50K characters, split into overlapping chunks (~40K with 2K overlap) and summarize each chunk before merging. For very long livestreams, a useful inspection pattern is grouping transcript segments into 10-20 minute timestamp buckets in browser JS or Python, then synthesizing the final answer from those buckets instead of dumping the whole transcript into context.
5. **Transform/save** into the requested output format. If the user did not specify a format and an Obsidian vault is available, default to creating an Obsidian source note under `Knowledge/Sources/Videos/` using the durable-note pattern above. Only default to chat summary when the user explicitly asks not to save or when no vault can be resolved. If the user says `retorne apenas em chat`, `não salve no Obsidian`, or gives an exact chat format, obey that explicitly and do not create/update notes.
6. **Verify**: re-read the transformed output or the first lines of the Obsidian note to check for coherence, correct metadata/timestamps, and completeness before presenting.

## Local transcription fallback

If `youtube-transcript-api` or subtitle download is blocked/rate-limited but the video itself is accessible, fall back to local transcription before telling the user transcripts are unavailable. See `references/local-transcription-fallback.md` for the compact recipe: inspect metadata with `yt-dlp --dump-json`, download audio only, transcribe with `uv run --with mlx-whisper ...`, then summarize from saved JSON segments grouped into 3-5 minute windows.

## Error Handling

- **Transcript disabled**: tell the user; suggest they check if subtitles are available on the video page.
- **Private/unavailable video**: relay the error and ask the user to verify the URL.
- **No matching language**: retry without `--language` to fetch any available transcript, then note the actual language to the user.
- **Dependency missing**: run `uv pip install youtube-transcript-api` and retry.
- **YouTube transcript/subtitle IP blocks or HTTP 429**: do not immediately give up if the video itself is downloadable. Fallback path:
  1. Fetch metadata with `yt-dlp --skip-download --dump-single-json` or the metadata print command.
  2. Download audio only with `yt-dlp --cookies-from-browser chrome -f 'bestaudio[ext=m4a]/bestaudio' --extract-audio --audio-format m4a -o '/tmp/<id>/audio.%(ext)s' "URL"`.
  3. Prefer a fast local transcription fallback on Apple Silicon: `uv run --with mlx-whisper python -c 'import mlx_whisper; r=mlx_whisper.transcribe("/tmp/<id>/audio.m4a", path_or_hf_repo="mlx-community/whisper-tiny", language="pt"); open("/tmp/<id>/transcript.txt","w").write(r["text"])'`.
  4. If using a larger MLX Whisper model, use the MLX-suffixed repo IDs (for example `mlx-community/whisper-small-mlx`). `mlx-community/whisper-small` can return HuggingFace 401/repository-not-found because that repo ID is not the converted MLX model.
  4. Validate the produced transcript length and inspect chunks before summarizing. Tiny models are noisy; use the transcript for gist/key ideas and avoid over-precise quotes unless verified. When an Obsidian/video note is created from local Whisper fallback rather than official captions, add a short provenance warning in the note explaining that transcript APIs/subtitles were blocked and that the synthesis came from local audio transcription, so quotes should be verified against the video.
  5. If local transcription times out with `openai-whisper`, try `mlx-whisper` before reporting a blocker.

## Fallbacks when YouTube transcript endpoints are blocked

When the user asks for chat-only output and says not to use the browser if a transcript is available, exhaust transcript/audio paths before browser automation:

1. Try the helper with explicit language fallback, e.g. `--language pt,pt-orig,en --timestamps`.
2. If the helper returns IP/request blocking (often 429), try `yt-dlp --skip-download --list-subs URL` to confirm whether manual or automatic captions exist.
3. If subtitles are listed but subtitle download/timedtext returns 429, try `yt-dlp --dump-single-json --skip-download URL` for title/channel/duration/description/tags and automatic caption metadata. Do **not** treat metadata alone as a transcript, but use it for grounding if an audio fallback is needed.
4. If a transcript is still required and audio download is available, download audio with `yt-dlp --cookies-from-browser chrome -f bestaudio/best --extract-audio --audio-format mp3 --audio-quality 7 -o /tmp/<video_id>_audio.%(ext)s URL`, then transcribe locally.
5. For long videos, split audio before Whisper to avoid timeouts: `ffmpeg -hide_banner -loglevel error -y -i /tmp/<video_id>_audio.mp3 -f segment -segment_time 300 -c copy /tmp/<video_id>_chunk_%03d.mp3`. Five-minute chunks are safer than ten-minute chunks on slower local Whisper installs.
6. Transcribe chunks with a small model first (`uv run --with openai-whisper whisper /tmp/<video_id>_chunk_000.mp3 --language Portuguese --model tiny --output_dir /tmp --output_format txt --fp16 False`). If time is limited, summarize only what was actually transcribed plus the verified video metadata, and explicitly avoid implying a full-transcript summary.
7. Use the browser only after these transcript/audio paths fail or when the task requires visual/player interaction.
