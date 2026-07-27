# AI Context Stack

Layered Markdown prompts compiled into local Ollama models, plus an eval suite to
pick the best model for each job. There is no fine-tuning here: behavior comes
from `prompts/`, durable memory, reusable knowledge files, and each model
builder's sampler/context params.

**What this is for:** running a small, opinionated set of local models on one
workstation, wiring them into editor assistants (Continue / Cline), and keeping
an evidence-based record of which model wins which task.

**What the testing is for:** every model in the lineup is benchmarked on speed,
coding, content/SEO, learning, and leak-gated tutoring so the "which model"
decision is measured, not guessed.

This README is the **guide**: what the project is, how to build and run models,
how to run the evals, and how to plug the models into VSCode. The benchmark
**record** — full runner docs, safety notes, history, and detailed results —
lives in [`TESTING.md`](TESTING.md).

## Models

Current lineup (rebuilt 2026-07-27):

| Model | Base | ctx | Role |
|---|---|---:|---|
| `gemma` | `gemma4:26b-a4b-it-qat` | 32K | 26B A4B MoE, QAT. Unbenchmarked on this base. |
| `qwen` | `hf.co/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q4_K_M` | 32K | 35B A3B MoE, uncensored community tune. Unbenchmarked on this base. |

Both are MoE: few active parameters per token, so CPU spillover stays usable on a
10 GB card even though neither fits fully in VRAM.

> **⚠ No current benchmark data.** Both bases changed on 2026-07-27 and the
> previous lineup (`gemma4:12b-it-q4_K_M`, `qwen3.6:35b-a3b-mtp-q4_K_M`) is no
> longer installed. **Every score in this file was measured against those retired
> bases and does not describe the models you have.** Roles above are
> architectural facts, not measured results. Run
> `./eval/run-profile.py standard --models gemma qwen` before trusting any pick.
>
> Two extra caveats on the new `qwen`: it is an *uncensored* tune, so it works
> against [`prompts/safety.md`](prompts/safety.md) by construction, and it is a
> newly-pulled community model that the execution runners run un-sandboxed —
> see the safety note in [`TESTING.md`](TESTING.md).

## Quickstart


```bash
./build-qwen
ollama run qwen
```

Each `build-*` script assembles the prompt stack, writes
`models/<name>/system.txt` and `models/<name>/Modelfile`, then runs
`ollama create <name> -f models/<name>/Modelfile`.

## Structure

```text
.
├── prompts/              # behavior controls; runs every turn
├── memory/user.md        # durable user profile
├── knowledge/**/*.md     # reusable reference context
├── eval/                 # benchmark runners and tasks
├── models/<name>/        # generated system.txt + Modelfile
└── build-qwen
```

Prompt assembly order is `knowledge/`, then `memory/`, then `prompts/`; files
within each directory are sorted. That keeps reference context first and behavior
rules last. Each Markdown file is wrapped in `--- START/END FILE ---`. Files over
100k are skipped. Builders abort if the assembled prompt contains `"""`, because
that would break the Ollama `SYSTEM """..."""` block.

## Build And Tune

The only model-specific part of a builder is the top config block:

```bash
MODEL_NAME="qwen"
BASE_MODEL="hf.co/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q4_K_M"
EXTRAS=()
PARAMS=( # Context: 262144 - 131072 - 65536 - 32768 - 16384 - 8192 - 4096
  'num_ctx 32768'         # 32k: The sweet spot for multi-file local tasks
  'temperature 0.2'       # Low temperature forces strict compliance with code syntax and tool tags
  'top_p 0.95'
  'top_k 40'
  'min_p 0.05'            # Safeguards structural format without restricting code vocabulary
  'presence_penalty 0.0'  # MUST BE ZERO. Coding requires reusing exact variable names.
  'repeat_penalty 1.05'   # Prevents infinite code loops without breaking boilerplate code
)

```

For a new model, copy an existing `build-*` script and edit only that config
block. The shared assembly section below the divider is mirrored across builders
and should stay byte-identical. Builders abort up front if `BASE_MODEL` is not
pulled, so a stale or retargeted base fails loudly instead of leaving a
half-written `system.txt` behind.

**Keep `PARAMS` identical across builders.** Only `run-json.py` sends sampler
options; every other suite inherits whatever the Modelfile sets. Differing values
across builders mean the leaderboard measures model × sampler instead of model —
that mistake invalidated the 2026-06-14 coding, learning, and tutor tables, which
compared `gemma` at `temperature 0.75` / `presence_penalty 0.2` against `qwen` at
`0.2` / `0.0`. If a model needs its own decoding for daily use, make that a
separate tag rather than skewing the shared baseline.

Where changes belong:

| Change | File |
|---|---|
| Behavior rule for all models | `prompts/` |
| Stable user preference/fact | `memory/user.md` |
| Reusable technical reference | `knowledge/` |
| New coding eval task | `eval/coding_tasks.py` |
| New content eval task | `eval/content_tasks.py` |
| New JSON/long-context eval task | `eval/json_tasks.py` |
| New learning/tutor eval task | `eval/learning_tasks.py` / `eval/tutor_tasks.py` |

Keep prompt text terse. Every prompt token is spent every turn; prefer removing
bad rules or tuning `PARAMS` before adding more instructions.

## Ollama Server

Local service override:

```ini
# sudo systemctl edit ollama
[Service]
Environment="OLLAMA_KV_CACHE_TYPE=q4_0"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_KEEP_ALIVE=10m"
```

Common commands:

```bash
sudo systemctl status ollama
sudo systemctl edit ollama
sudo systemctl daemon-reload
sudo systemctl restart ollama

ollama list
ollama ps
ollama show gemma
ollama run gemma
ollama run qwen
```

## Use In VSCode (Continue / Cline)

Both extensions talk to Ollama's local API at `http://localhost:11434`. Build the
models first (`./build-qwen`, `./build-gemma`) so the custom names resolve, then
confirm they are loaded with `ollama list`.

### Continue

Add the built models to `~/.continue/config.yaml` (Continue's provider name for
Ollama is `ollama`; `model` is the Ollama model name):

```yaml
models:
  - name: qwen (coding/learning)
    provider: ollama
    model: qwen
    roles: [chat, edit, apply]
  - name: gemma (content/fast)
    provider: ollama
    model: gemma
    roles: [chat, edit, apply]
```

Which one to default to is currently an open question — the previous
recommendation rested on the retired bases. `gemma` is the smaller of the two
(15 GB vs 22 GB), so it is the reasonable interim default on load time alone until
a `standard` pass says otherwise. Continue auto-discovers Ollama, but listing the
custom names keeps the prompt-stacked builds (not the raw bases) in the model
picker.

### Cline

In Cline's settings, set **API Provider** to `Ollama`, **Base URL** to
`http://localhost:11434`, and **Model** to `qwen` or `gemma`. Cline is
agentic/coding-heavy and ingests large prompts, so prompt-eval throughput matters
more here than generation speed — `run-speed.py` reports both, and that column
should drive the choice once the current bases are measured.

Notes for both: keep `OLLAMA_KEEP_ALIVE` long enough to avoid reload churn when
switching models. Neither current base fits entirely in 10 GB of VRAM, so expect
CPU spill on both; both are MoE, which is what keeps that spill usable.

## Evaluation

Runners live under `eval/` and write results to `eval/runs/<UTC>/`. Routine
testing goes through profiles (`smoke` after a rebuild, `standard` for the
under-1-hour comparison, `deep` for a several-hour confidence run — see
[`TESTING.md`](TESTING.md) for when to use each):

```bash
./eval/run-profile.py smoke --models qwen gemma
./eval/run-profile.py standard --models qwen gemma
```

Individual runners remain available for targeted sweeps:

```bash
./eval/run-speed.py --models qwen gemma
./eval/run-code.py --models qwen gemma
./eval/run-content.py --models qwen gemma
./eval/run-learn.py --models qwen gemma
./eval/run-tutor.py --models qwen gemma
./eval/run-json.py --models qwen gemma
```

`run-json.py` is the structured-output test the consumer apps (Jobhunt,
SEO-LLM) depend on: it constrains decode with a JSON schema, buries facts in a
multi-thousand-token document, and scores schema conformance plus long-context
fact recall. It pins `num_ctx 32768` to match how those apps call Ollama.

`run-code.py`, `run-learn.py`, and `run-tutor.py` execute model-generated Python
with timeouts but are not containerized. Run trusted models only. Full runner
flags and safety details are in [`TESTING.md`](TESTING.md).

## Benchmark Leaderboard

> **⚠ RETIRED BASES — does not describe the current lineup.** Everything in this
> section was measured on 2026-06-14 against `gemma4:12b-it-q4_K_M` and
> `qwen3.6:35b-a3b-mtp-q4_K_M`, neither of which is installed. It is also
> sampler-confounded (see *Build And Tune*): the two models ran at different
> temperatures, so the coding, learning, and tutor tables do not isolate model
> quality. Kept for decision history only. Rerun before picking anything.

Latest full Gemma/Qwen head-to-head: 2026-06-14, all six suites in one
`standard` pass (3 attempts/task). Treat small score gaps as directional:
failures are strong signal, close wins are weak signal, and speed breaks quality
ties. Samples are small and learn/tutor /10 rests on a single judge per response.

| Suite | Winner | `gemma` | `qwen` |
|---|---|---:|---:|
| Speed | `gemma` | 54.0 tok/s, 100% GPU | 46.7 tok/s, 74%/26% CPU/GPU |
| Coding | tie | 26/27 | 26/27 |
| Content | `gemma` | 9/9 clean | 7/9 clean |
| Learning | tie | 9.7/10, code 12/12 | 9.2/10, code 11/12 |
| Tutor (leak-gated) | `gemma` | 6.9/10, leaks 3/15 | 3.8/10, leaks 9/15 |
| JSON / long-context | `gemma` | 100%, 2.9s avg, 50 tok/s | 100%, 6.7s avg, 48 tok/s |

Current picks (⚠ all from the retired bases above — not valid for the current
lineup):

| Use | Pick | Reason |
|---|---|---|
| Content / SEO / copy | `gemma` | 9/9 clean vs `qwen` 7/9; ~2× faster and fully on GPU. |
| Coding puzzles / small functions | `gemma` / `qwen` (tie) | Both 26/27; break on speed/GPU → `gemma`. `gemma`'s only miss is `calc`. |
| Learning explanations | `gemma` / `qwen` (tie) | `gemma` 9.7 vs `qwen` 9.2 (within threshold); `qwen` explains better but dropped a code gate. |
| Socratic tutoring (no spoilers) | `gemma` | Leak-gated `run-tutor.py`: 6.9/10 with 3/15 leaks vs `qwen`'s 3.8 with 9/15. |
| Structured JSON / app smoke tests | `gemma` | Both scored 100%; `gemma` ~2× faster (2.9s vs 6.7s) in `eval/runs/20260614T201535Z/json/summary.md`. |
| Fast local general use | `gemma` | Best fit/speed and no CPU spill. |

## Models Tested

Per-suite /10 for the **retired** 2026-06-14 bases (speed and rate-based suites
normalized to the best result). Retained as history; the current bases have no
scores yet:

```text
          gemma4:12b-it-q4_K_M          qwen3.6:35b-a3b-mtp
Speed    10.0  ████████████████████  |  8.6  █████████████████
Coding    9.6  ███████████████████   |  9.6  ███████████████████
Content  10.0  ████████████████████  |  7.8  ████████████████
Learning  9.7  ███████████████████   |  9.2  ██████████████████
Tutor     6.9  ██████████████        |  3.8  ████████
JSON     10.0  ████████████████████  | 10.0  ████████████████████
```

Full roster (current and retired). See [`TESTING.md`](TESTING.md) for the reasoning:

| Model | Base | Status |
|---|---|---|
| `gemma` | `gemma4:26b-a4b-it-qat` | current — rebuilt 2026-07-27, **unbenchmarked** |
| `qwen` | `hf.co/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q4_K_M` | current — rebuilt 2026-07-27, **unbenchmarked**; uncensored community tune |
| `gemma` (prior) | `gemma4:12b-it-q4_K_M` | retired 2026-07-27 — base no longer installed; source of the 2026-06-14 scores |
| `qwen` (prior) | `qwen3.6:35b-a3b-mtp-q4_K_M` | retired 2026-07-27 — base no longer installed; source of the 2026-06-14 scores |
| `gemma-custom` | `gemma4:e4b` | removed — superseded by gemma4 12B |
| `granite-custom` | `granite4.1:8b-Q5_K_M` | dropped — strong prior coding, no longer leads |
| `qwen-custom` | `qwen3.5:9b` | removed — superseded by Qwen3.6 MoE |
| `ministral-custom` | `ministral-3:8b` | removed — historical #2 |
| `llama-custom` | `llama3.1:8b` | removed — trailed in early runs |
| `gemma-big` | `gemma3:27b` | retired — lost the quality/speed tradeoff on this box |

## Hardware Envelope

Benchmarks are for this box: RTX 3080 10 GB, Ryzen 5900x, 32 GB DDR4-3600.
Models that fit 100% on GPU run fast. Dense spillover is usually too slow; MoE
spillover can remain usable because fewer parameters are active per token.

## Docs

- [`TESTING.md`](TESTING.md): testing source of truth, runner docs, safety notes,
  benchmark history, and detailed results.
