# Local transcription fallback for YouTube videos

Use this when YouTube captions exist but transcript fetches are blocked/rate-limited (for example `youtube-transcript-api` RequestBlocked/IPBlocked or `yt-dlp --write-subs` HTTP 429). Do not treat this as "no transcript" until a fallback has been tried.

Observed robust path on macOS:

1. Confirm metadata/caption availability without downloading captions:
   `yt-dlp --skip-download --dump-json "URL"`
   Inspect title, duration, `subtitles`, and `automatic_captions`.

2. Download audio only:
   `yt-dlp -f 'bestaudio[ext=m4a]/bestaudio' --max-filesize 100M -o '/tmp/<video_id>_audio.%(ext)s' "URL"`

3. Transcribe locally with MLX Whisper when available via uv:
   `uv run --with mlx-whisper python3 -c "import mlx_whisper, json; r=mlx_whisper.transcribe('/tmp/<video_id>_audio.m4a', path_or_hf_repo='mlx-community/whisper-small-mlx'); open('/tmp/<video_id>_mlx.json','w').write(json.dumps(r)); print(len(r.get('text','')))"`

4. Summarize from the saved JSON. For short/medium videos, group `segments` into ~3 minute windows and inspect every bucket before writing the final note; for long videos, use 3-5 minute windows or split audio first if transcription times out.

5. When the YouTube API is blocked but `yt-dlp --list-subs` shows `pt-orig`/`pt` captions and `yt-dlp --write-auto-subs` returns HTTP 429, do not keep retrying subtitle downloads. Treat it as a rate-limit path and move to audio transcription. A robust command on Apple Silicon is:
   `uv run --with mlx-whisper python3 -c "import mlx_whisper, json; r=mlx_whisper.transcribe('/tmp/<video_id>/audio.m4a', path_or_hf_repo='mlx-community/whisper-small-mlx', language='pt'); open('/tmp/<video_id>/transcript_mlx.json','w').write(json.dumps(r, ensure_ascii=False)); open('/tmp/<video_id>/transcript_mlx.txt','w').write(r.get('text','')); print({'text_len': len(r.get('text','')), 'segments': len(r.get('segments',[]))})"`

Notes:
- This is a fallback for accessible public videos when caption HTTP calls are blocked; it is not a durable claim that YouTube transcript tools are broken.
- Prefer the user's requested delivery. If they explicitly say chat-only / do not save to Obsidian, do not create a note even when the default workflow is Obsidian.
- When a durable Obsidian note is created from local Whisper output, include a short caveat in `Riscos / críticas` or `Fonte da transcrição` that the transcript came from local audio and should not be used for exact quotes without manual verification.
- Mention transcript source only if relevant; otherwise return the requested formatted result.