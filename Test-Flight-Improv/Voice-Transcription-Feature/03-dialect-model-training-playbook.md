# Dialect model training playbook — how to make a small on-device model good at a dialect

Captured from the 2026-07-14 research session so the Syrian (or any next-dialect) effort
can resume without re-deriving anything. Dialect-agnostic; Egyptian and Syrian notes inline.
Data sources live in [01-shippable-training-resources.md](01-shippable-training-resources.md);
Syrian landscape in [02-syrian-dialect-research.md](02-syrian-dialect-research.md).

## Ground rules

- **Fine-tune, never pretrain from scratch.** From-scratch needs 10k+ hours and SSL
  expertise (Munsit/Ara-BEST-RQ territory). Fine-tuning rides on what the base already knows.
- **"Local LLM" means a speech-to-text model here** (Whisper family / FastConformer),
  not a text LLM. A text LLM can only post-process (punctuation, summaries) later.
- **Expectation setting**: dialectal Arabic ASR after fine-tuning lands ~25–60% WER /
  8–27% CER depending on dialect (NADI 2025 fine-tuned Whisper-medium: Jordan 25.3%/7.7%
  best → Mauritania 62.8%/27.0% worst). Arabic WER is inflated by orthographic variation;
  a 30%-WER voice-note transcript is a readable gist. The product target is *useful gist*,
  and UX copy must frame it that way.

## The four ingredients

### 1. Data (the bottleneck — everything else is cheap)

- **Quantity tiers**: ~10–30h per dialect already moves a lot (28.4h of Egyptian took
  Whisper-medium from 78.8% → 57.1% WER in the 2025 data-scarcity study, arXiv:2506.02627);
  100–500h = solid; SOTA shops use ~30k weakly-labeled hours (Munsit, arXiv:2508.08912).
- **Domain match beats volume**: spontaneous, conversational, phone-mic speech with
  code-switching (ar↔en; for Syrian diaspora also ar↔de). Read-speech corpora
  (Common Voice) transfer poorly — use them as mix-in/regression data only.
- **Augment everything**: noise, reverb, speed perturbation, SpecAugment, and
  **AAC-LC re-encode** to match our voice-note codec (`audio/mp4`,
  `lib/core/media/record_audio_recorder_service.dart`).
- **Bulk lever = pseudo-labeling**: scrape *spoken* web audio (podcasts, vlogs,
  interviews), filter by dialect-ID (ADI-17/20 cover Syria), transcribe with a strong
  teacher, keep high-confidence segments (uDistil-Whisper recipe, arXiv:2407.01257).
  Needs counsel sign-off (doc 01 §A9).
- **Never songs/lyrics-site pairs**: technically wrong (singing acoustics ≠ speech; ASR
  pipelines filter music OUT; lyrics aren't time-aligned and diverge from what's sung;
  poetic vocabulary ≠ conversational) and legally the worst category (three copyright
  stacks per song; music industry actively litigates AI training; lyrics sites hold
  display-only licenses). If background-music robustness is the worry, mix instrumental
  beds under speech as augmentation instead.
- **Privacy line**: user voice notes are NEVER training data. Only an explicit opt-in
  donation flow could ever change that.

### 2. A spelling standard (the underrated ingredient)

Dialects have no standard orthography; inconsistent labels corrupt training and inflate
eval error. Adopt CODA/CODA* conventions for anything we commission; define eval
normalization (hamza/alif variants, taa marbuta, diacritics); always report **CER
alongside WER**.

### 3. Recipe

- **Baseline**: LoRA fine-tune of whisper-small on gold dialect data. LoRA ≈ full
  fine-tuning (within ~0.6 WER pt) at a fraction of the cost. Merge adapter → convert
  to ggml/ONNX → deploys unchanged through whisper.cpp / sherpa-onnx.
- **Best quality-per-deployed-MB (two-stage)**: fine-tune a large teacher
  (Whisper large-v3; Egyptian: QwenCleo-ASR; Syrian: WhisperLevantine, Apache-2.0)
  → pseudo-label bulk audio → distill into the on-device student.
- **Student alternatives**: NVIDIA FastConformer-ar (~115M params, tops the Open
  Universal Arabic ASR Leaderboard where Whisper large-v3 sits third at ~37% avg WER)
  — verify checkpoint license (doc 01 §B).
- **Anti-forgetting**: mix some English/MSA (and German if ar↔de matters) into
  fine-tuning so code-switched and non-Arabic notes don't regress.
- **Compute**: single A100/4090-class GPU, hours-to-days, ~$50–500 per experiment.
  One ML-comfortable engineer suffices until the distillation stage.

### 4. Eval set BEFORE anything else

2–5h of real voice-note-style speech per target dialect (spontaneous, phone mic,
code-switching, names, numbers), transcribed under the CODA guideline, held out
forever. It first answers "do we even need to train?" and then scores every
experiment. Per-dialect breakdown + MSA/en (and de) regression checks + a human
"is this transcript useful?" rating.

## The ladder (per dialect)

1. **Benchmark existing checkpoints** on the eval set — stock Whisper small/large-v3,
   community fine-tunes (Egyptian: whisper-small-egyptian-arabic; Levantine/Syrian:
   WhisperLevantine, otozz/whisper-small-dialect_levantine), QwenCleo-ASR as ceiling.
   The project can end here if someone already trained what we need.
2. **Prototype LoRA fine-tune** of whisper-small on research-licensed data (blocklist
   §D of doc 01 — prototype only, never shipped) to measure the achievable gain
   before spending money.
3. **Buy/unblock the commercial pile** (doc 01 §A, doc 02 for Syrian) and train the
   shippable model on clean data only.
4. **Scale via teacher → pseudo-label → distill** if step 3 quality is still short.
5. Ship tiered by device (see integration constraints below).

## On-device integration constraints (from the feasibility pass)

- Runtime: whisper.cpp via FFI or sherpa-onnx Flutter plugin; the app already ships
  native libs on both platforms (`android/app/libs/GoMknoon.aar`, `ios/GoMknoon.podspec`).
- Model tiers: tiny q5 ~32MB/~100MB RAM (Arabic unusable) · base q5 ~60MB/~200MB (weak)
  · **small q5 ~190MB/~400–550MB RAM — the Arabic floor**; ~1–2× audio duration on
  mid-range Android CPUs, faster on iPhone (Metal/Core ML).
- Decode AAC→16kHz mono PCM with platform decoders (AVAudioConverter / MediaCodec);
  no FFmpeg (FFmpegKit is retired).
- UI hook: single shared `AudioPlayerWidget`
  (`lib/shared/widgets/media/audio_player_widget.dart`, used from `letter_card.dart`,
  feed `letter_bubble.dart`, posts, media grid) reading `attachment.localPath`.
- Transcript cache: new SQLCipher table keyed by attachment id + model version;
  local-only, never synced; **must join the private-media deletion lifecycle**
  (clearLocalCopy sweeps — otherwise deleted media leaves a plaintext transcript behind).
- No auto-transcribe in the iOS Notification Service Extension (~24MB budget) —
  feature is on-demand, foreground, tap-to-transcribe.
- Don't bundle models in the binary: download on first use with checksum; offer
  "delete model" in storage settings; gate tier by RAM/ABI (minSdk 24 hardware exists).

## Key references

- Data scarcity / Whisper fine-tuning: arXiv:2506.02627 · NADI 2025: https://nadi.dlnlp.ai/2025/
  (system paper arXiv:2511.10090) · Distillation: arXiv:2407.01257 · Munsit weak
  supervision: arXiv:2508.08912 · Leaderboard: Open Universal Arabic ASR (Interspeech 2025)
  · Survey: Arab Voices arXiv:2601.13319 · Casablanca: arXiv:2410.04527
