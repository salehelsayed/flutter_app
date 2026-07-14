# Shippable training resources — Arabic dialect ASR (voice-note transcription)

Only resources that can legally back the **shipped commercial model** are listed.
Research-/non-commercial-licensed corpora are blocklisted at the bottom so nobody
re-adds them to a training set by accident. Licenses change: re-verify each entry
before the first real training run. Last verified: 2026-07-14.

## A. Training data — cleared or clearable for commercial use

| # | Resource | Dialect / domain | Size | How to get | Cost (ballpark) | License status |
|---|---|---|---|---|---|---|
| 1 | [Common Voice Arabic](https://commonvoice.mozilla.org/en/datasets) | MSA-leaning, read speech | ~100h+ validated | Direct download | Free | ✅ CC0. Use as mix-in/regression data, not dialect signal |
| 2 | LDC CALLHOME Egyptian family: [LDC97S45 speech](https://catalog.ldc.upenn.edu/LDC97S45), [LDC97T19 transcripts](https://catalog.ldc.upenn.edu/LDC97T19), [LDC2002S37](https://catalog.ldc.upenn.edu/LDC2002S37)/[LDC2002T38](https://catalog.ldc.upenn.edu/LDC2002T38) supplements, [LDC2025T14 BOLT transcripts](https://catalog.ldc.upenn.edu/LDC2025T14) | Egyptian, unscripted telephone calls | 120 calls; ~20h transcribed (+supplements) | LDC account; fees shown after login | Typically ~$1–2.5k per part (non-member) | ✅💰 LDC licenses to companies — **confirm commercial terms before purchase** |
| 3 | LDC Levantine family: [Fisher Levantine speech LDC2007S02](https://catalog.ldc.upenn.edu/LDC2007S02) + [transcripts LDC2007T04](https://catalog.ldc.upenn.edu/LDC2007T04); superset QT Training Set 5 (LDC2006S29); Babylon Levantine (LDC2005S08) | Levantine (mostly Jordan/Lebanon/Palestine), telephone calls | 279 calls / 45h (Fisher) | LDC, as above | As above | ✅💰 Same LDC terms. See doc 02 for Syrian fit |
| 4 | [FutureBeeAI Egyptian packs](https://www.futurebeeai.com/dataset/speech-data/arabic-dataset) | Egyptian general conversation (~50h, 70 speakers) + call-center packs (30–40h/domain) | 50h+ | Contact sales | Quote; off-the-shelf transcribed speech runs roughly $50–150/h industry-wide | ✅💰 sold with commercial rights. **No Syrian/Levantine offered** (Egyptian/Algerian/Saudi only) |
| 5 | [Nexdata Arabic catalog](https://www.nexdata.ai/datasets/speechrecog) | MSA, Gulf, **Levantine** (Jordan/Lebanon collection), Egyptian; conversation + monologue; also [849h Saudi spontaneous](https://github.com/Nexdata-AI/849-Hours-Saudi-Arabic-Spontaneous-Speech-Data), [100k h unsupervised](https://github.com/Nexdata-AI/100000-hours-Arabic-Unsupervised-speech-dataset) | varies | Contact sales | Quote | ✅💰 commercial vendor |
| 6 | [Macgence Syrian general conversation](https://data.macgence.com/dataset/general-conversation-speech-dataset-of-general-sector-in-arabic-syria) | **Syrian**, general conversation | unlisted | Contact sales | Quote | ✅💰 commercial vendor — one of the few Syrian-specific offers |
| 7 | [Defined.ai Arabic spontaneous dialogue](https://defined.ai/datasets/arabic-spontaneous-dialogue) | Arabic spontaneous dialogue | varies | Marketplace | Quote | ✅💰 commercial marketplace |
| 8 | Custom collection (contractors/community) | Exactly our domain: voice-note-style, target dialects, ar↔en / ar↔de code-switching | As commissioned | Run ourselves or via vendor (Appen/LXT/Shaip class) | ~$1–3 per transcribed audio-minute + speaker payments (≈$60–180/h) | ✅ full rights; best domain match; requires CODA-style spelling guideline first |
| 9 | Pseudo-labeled scraped **spoken** web audio (podcasts, vlogs, interviews) | Any dialect; the bulk-scale lever | Effectively unbounded | Scrape → dialect-filter (ADI-17/20 classifiers) → label with a strong teacher (sec. B) → confidence-filter | Compute only | ⚠️ Standard industry practice (uDistil-Whisper / Munsit recipe) but **needs counsel sign-off for our jurisdictions**. Spoken content only — never songs/music/lyrics (separate copyright stack, actively litigated) |
| 10 | [MASC](https://ieee-dataport.org/open-access/masc-massive-arabic-speech-corpus) | Multi-dialect YouTube, 1,000h — includes **~197h Syrian** ([Arab Voices survey](https://arxiv.org/html/2601.13319v2)) | 1,000h (169GB tarball) | Free IEEE DataPort account | Free | ⚠️ **BLOCKED on verification**: page states "open access" but names no license. If the authors confirm a permissive license, this is the single largest shippable dialect source. Contact via DataPort messaging |

## B. Runtimes and model weights (deployable / usable in the pipeline)

| Component | Role | License |
|---|---|---|
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | On-device inference (FFI) | MIT ✅ |
| OpenAI Whisper weights (tiny→large-v3) | Base + fine-tune starting points; large-v3 as teacher | MIT ✅ |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | Alternative on-device runtime with official Flutter plugin | Apache-2.0 ✅ |
| [WhisperLevantine](https://huggingface.co/HebArabNlpProject/WhisperLevantine) | Levantine teacher/benchmark (large-v3 fine-tune, ~1,200h, reports 33% WER) | Apache-2.0 ✅ — see doc 02 caveats |
| [NVIDIA FastConformer ar](https://huggingface.co/nvidia/stt_ar_fastconformer_hybrid_large_pc_v1.0) | Phone-sized (~115M) non-Whisper student candidate; tops the Open Universal Arabic ASR Leaderboard | ⚠️ verify model-card license before shipping |
| QwenCleo-ASR (Qwen3-ASR-1.7B fine-tune) | Egyptian + code-switching SOTA; teacher/labeler only (too big for mid-range devices) | ⚠️ verify license before pipeline use |

## C. Assets we must build ourselves (full rights by construction)

1. **Eval sets** — 2–5h per target dialect of real voice-note-style speech (spontaneous,
   phone mic, incl. ar↔en and ar↔de code-switching, names, numbers). Built before any
   training; this is the yardstick for every experiment and the spike deliverable.
2. **Spelling convention** — CODA*-based transcription guideline handed to every
   annotator/vendor; also defines eval normalization (hamza/alif/taa-marbuta/diacritics).
   Report CER alongside WER.
3. **Augmentation recipe** — noise/reverb/speed + **AAC-LC re-encode** to match the
   voice-note codec (`audio/mp4`, `record_audio_recorder_service.dart`).

## D. Blocklist — research/NC licenses, must NOT train the shipped model

Benchmarking and throwaway prototypes only: Casablanca (CC BY-NC-ND) · NADI 2025 ASR ·
SADA (CC BY-NC-SA) · MGB-2 / MGB-3 / QASR (QCRI research agreements) · ASR-EgArbCSC
(MagicHub non-commercial) — including any Hugging Face mirrors of these (mirrors do not
change the license).

## E. Budget sketch (Egyptian-first, ballparks)

- Prototype (blocklist data, proves fine-tuning closes the gap): **$0** + GPU time (~$50–500)
- LDC CALLHOME Egyptian bundle with commercial terms: **~$2–6k** (confirm with LDC)
- Vendor conversational pack, 40–80h: **~$3–10k**
- Custom 50h voice-note-style collection: **~$5–15k**
- Pseudo-label pipeline at scale: mostly compute + legal review

## F. Open acquisition actions

- [ ] MASC license inquiry via IEEE DataPort (unblocks item 10 — and ~197h Syrian)
- [ ] LDC account + written confirmation of commercial licensing for items 2–3
- [ ] Vendor quotes: Nexdata (Levantine), Macgence (Syrian), FutureBeeAI (Egyptian)
- [ ] Counsel review of the pseudo-labeling lever (item 9)
- [ ] Verify FastConformer-ar and QwenCleo-ASR licenses if either enters the pipeline
