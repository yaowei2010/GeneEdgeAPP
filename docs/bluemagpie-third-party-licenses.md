# BlueMagpie Android PoC third-party inventory

This inventory applies only when the debug-only `bluemagpiePoc` build flag is
enabled. Model files are not included in Git, APK, or AAB artifacts.

| Component | Pinned source | Declared license | PoC use |
| --- | --- | --- | --- |
| `mybigday/llama.rn` codec branch | `7d5cf82cf33883bc80ec845905f5d85c5565d132` | MIT (`LICENSE`) | C++ runtime source only |
| vendored llama.cpp/ggml source under `cpp/` | included by the pinned commit; upstream snapshot `c926ad09857517978575d6a74d225b463f7417a0` | MIT (`cpp/LICENSE`) | model and tensor runtime |
| codec implementation under `cpp/codec/` | included by the pinned commit; its metadata references codec.cpp snapshot `c5ef02b12bf4129b10aad0a463637c7372f9572f` | review required | AudioVAE and continuous-latent decode |
| `hans00/BlueMagpie-TTS-GGUF` conversion | `37ab65a2836e6cf5780f2e5566ae77ca5967982f` | Apache-2.0 declared by conversion repository | manually installed GGUF files |
| `OpenFormosa/BlueMagpie-TTS` upstream weights | `aaf1a0878e37875382bb0e5c8a3a2ba43be67297` | model card declares `other` | provenance only; legal review required |
| OpenBMB/VoxCPM architecture lineage | recorded in `bluemagpie-models.json` | upstream-specific | disclosed mainland-China architecture provenance |

The app does not include npm packages, React Native, a JavaScript engine, or
JSI. Only files below `third_party/llama.rn-codec/cpp` may be referenced by the
native PoC target. The unresolved codec/upstream-weight license rows block a
production release until the project owner completes a license review.
