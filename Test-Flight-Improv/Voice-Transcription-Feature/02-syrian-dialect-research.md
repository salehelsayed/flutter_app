# Syrian dialect (North Levantine) — ASR resource research

Research pass: 2026-07-14. Question: what exists to make voice-note transcription
work for **Syrian Arabic** specifically, and what has to be built/bought.

## TL;DR

There is **no sizable public Syrian-specific conversational corpus**. Syrian coverage
has to be assembled from four levers: (1) MASC's ~197h Syrian subset — the biggest
single source, currently blocked on license verification; (2) LDC's Levantine telephone
corpora (buyable, but South-Levantine-leaning); (3) vendor data (Macgence sells a
Syrian conversational set; Nexdata sells Levantine); (4) pseudo-labeling scraped
Syrian spoken audio, filtered by a dialect-ID model. The good news: Levantine is one
of the more tractable dialect groups (NADI 2025 fine-tuned baselines hit ~25% WER /
~7.7% CER on Jordanian, the best of eight dialects), and an Apache-2.0 Levantine
teacher model already exists.

## Linguistic framing

Syrian Arabic is **North Levantine** (shared continuum with Lebanese); Jordanian and
Palestinian are **South Levantine**. Most available "Levantine" data leans South
(Fisher speakers are mostly Jordan/Lebanon/Palestine) or Israeli-Levantine
(WhisperLevantine). That data still transfers far better to Syrian than MSA or
Egyptian does, but a Syrian-specific eval set is non-negotiable to measure the gap.

## Data landscape

| Resource | Syrian relevance | Size | Status |
|---|---|---|---|
| [MASC](https://ieee-dataport.org/open-access/masc-massive-arabic-speech-corpus) Syrian subset | Direct — ~197h Syrian per the [Arab Voices survey](https://arxiv.org/html/2601.13319v2) | ~197h of 1,000h | ⚠️ Free download; license unstated — verification is the top action (doc 01, item 10) |
| [Fisher Levantine speech LDC2007S02](https://catalog.ldc.upenn.edu/LDC2007S02) + [transcripts LDC2007T04](https://catalog.ldc.upenn.edu/LDC2007T04) | Adjacent (South Levantine lean); telephone conversations = close domain match | 279 calls / 45h | ✅💰 Buyable from LDC; superset: QT Training Set 5 (LDC2006S29); also Babylon Levantine (LDC2005S08) |
| [Macgence Arabic (Syria) general conversation](https://data.macgence.com/dataset/general-conversation-speech-dataset-of-general-sector-in-arabic-syria) | Direct — one of the few Syrian-specific commercial sets | unlisted | ✅💰 Request quote + sample; validate dialect authenticity before buying |
| [Nexdata Levantine packs](https://www.nexdata.ai/datasets/speechrecog) | Adjacent (Jordan/Lebanon collection sites) | varies | ✅💰 Quote |
| [Arabic Speech Corpus](http://en.arabicspeech.org/) (Damascus) | Nominally Syrian, but single-speaker studio MSA-with-Damascus-accent built for TTS (~1.8k utterances) | ~3–4h | Negligible ASR value; skip |
| [ArSyra/arsyra-levantine](https://huggingface.co/datasets/ArSyra/arsyra-levantine) | Levantine set on HF, provenance/license unknown | ? | Investigate before any use |
| SADA (Levantine slices), MGB-2 (Levantine broadcast) | Adjacent | minor | ❌ Blocklisted anyway (research licenses, doc 01 §D) |
| Casablanca / NADI 2025 (Jordan, Palestine) | Adjacent — **eval/prototype only** | ~4h+ Levantine-group | ❌ Blocklisted for the shipped model; fine as Levantine benchmark |

## Models

- **[WhisperLevantine](https://huggingface.co/HebArabNlpProject/WhisperLevantine)** —
  Whisper large-v3 fine-tuned on ~1,200h Levantine (primarily Israeli-Levantine, 8kHz
  telephone-style upsampled), reports 33% WER, **Apache-2.0**. Two roles for us:
  (a) zero-cost benchmark ceiling for Levantine, (b) teacher for pseudo-labeling
  Syrian audio. Caveats: South/Israeli-Levantine lexicon and phonology differ from
  Syrian; its telephone-band training may actually suit voice notes; verify behavior
  on ar↔de code-switching (likely poor).
- **[otozz/whisper-small-dialect_levantine](https://huggingface.co/otozz/whisper-small-dialect_levantine)** —
  a whisper-small Levantine fine-tune; useful as a "what does small look like" baseline.
- Stock Whisper small/large-v3 — always benchmark alongside, per the Egyptian ladder.

## Diaspora angle (product-relevant)

The app ships `ar`, `de`, `en` locales; a Syrian user base in Germany implies
**Arabic↔German code-switching** in real voice notes. No public ar↔de code-switched
speech corpus exists (ZAEBUC-Spoken covers Arabic↔English only), so this must be
covered by our own eval set and any custom collection (doc 01 §C1, §A8). Whisper
handles intra-utterance language switches poorly out of the box — measure it
explicitly in the Syrian eval set.

## Pseudo-labeling pipeline for Syrian (the scale lever)

1. Scrape Syrian **spoken** web audio: podcasts, YouTube vlogs/interviews, diaspora
   channels (never music/lyrics — see doc 01 item 9 legal note).
2. Filter to Syrian with a dialect-ID model (ADI-17/ADI-20 cover Syria) + VAD/music removal.
3. Label with WhisperLevantine and/or our own fine-tuned large-v3 teacher;
   keep high-confidence segments only (uDistil-Whisper-style filtering).
4. Mix with gold data (MASC-Syrian if cleared, LDC, vendor, custom) and train the
   on-device student (whisper-small class or FastConformer).

## Recommended Syrian ladder (mirrors the Egyptian one)

1. **Eval set first**: 2–5h Syrian voice-note-style speech incl. ar↔de code-switching.
2. **Benchmark**: stock Whisper small / large-v3, WhisperLevantine, QwenCleo-ASR.
3. **Prototype fine-tune** of whisper-small on Levantine-group research data
   (Casablanca Jordan/Palestine + NADI) to measure the achievable gain — not shippable,
   purely to de-risk spend.
4. **Unblock/buy**: MASC license (~197h Syrian) → LDC Fisher Levantine → Macgence/Nexdata
   quotes → custom collection for the voice-note domain.
5. **Scale** with the pseudo-label pipeline; distill into the on-device student.
