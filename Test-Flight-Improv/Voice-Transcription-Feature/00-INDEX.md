# Voice-Transcription-Feature — Index

Research artifacts for the planned on-device transcription of incoming voice notes
(local speech-to-text model; no audio or transcript ever leaves the device).

Status: research / pre-spike. No implementation started. Last updated: 2026-07-14.

| Doc | Contents |
|---|---|
| [01-shippable-training-resources.md](01-shippable-training-resources.md) | Data, model weights, and runtimes that are (or can be) licensed for use in the **shipped commercial model**. Research-only corpora are deliberately excluded and blocklisted. |
| [02-syrian-dialect-research.md](02-syrian-dialect-research.md) | Resource landscape and acquisition plan for **Syrian (North Levantine)** dialect coverage. |
| [03-dialect-model-training-playbook.md](03-dialect-model-training-playbook.md) | Full training playbook: data quantities, spelling standard (CODA), fine-tune/distill recipes, eval-first ladder, expectation setting, songs/lyrics ruling, and on-device integration constraints. Resume-point for the Syrian effort. |

Context: voice notes are recorded as AAC-LC in MP4 (`lib/core/media/record_audio_recorder_service.dart`),
played from `attachment.localPath` by `lib/shared/widgets/media/audio_player_widget.dart`.
Deployment target is a quantized Whisper-family model via whisper.cpp or sherpa-onnx,
so every training resource below must be commercially licensable end-to-end.
