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

Current lineup (rebuilt 2026-07-28):

| Model | Base | ctx | Role |
|---|---|---:|---|
| `gemma` | `gemma4:26b-a4b-it-qat` | 32K | 26B A4B MoE, QAT. Strongest prompt-ingest throughput. |
| `qwen` | `qwen3.6:35b-a3b-mtp-q4_K_M` | 32K | 35B A3B MoE. Largest model that stays usable here. |
| `lite` | `qwen3.5:9b` | 32K | Dense 9B. The only one that fits entirely in 10 GB — speed anchor and 3rd judge. |

`gemma` and `qwen` are MoE: few active parameters per token, so CPU spillover
stays usable on a 10 GB card even though neither fits fully in VRAM. `lite` is
dense but small enough to avoid spillover altogether, which is what makes it the
baseline the other two are measured against.

`lite` also exists for a measurement reason, not just a speed one: the learn and
tutor suites grade with a leave-one-out judge panel, so a 2-model lineup left
exactly one judge per response and inter-judge disagreement could never be
computed. Three models means two judges per response and a real disagreement
number.

## Quickstart


```bash
cp memory/user.example.md memory/user.md                          # then edit
cp memory/learning-profile.example.md memory/learning-profile.md  # then edit
make build        # builds gemma, qwen, and lite
ollama run qwen
```

The assembled system prompt carries a real user profile — skills, clients,
hardware — so `memory/*.md` is gitignored and only the `*.example.md` templates
are published. Seed them before the first build; the builders abort with the
copy commands above rather than quietly assembling a model with no profile.

Each `build-*` script assembles the prompt stack, writes
`models/<name>/system.txt` and `models/<name>/Modelfile`, then runs
`ollama create <name> -f models/<name>/Modelfile`.

## Structure

```text
.
├── prompts/              # behavior controls; runs every turn
├── memory/user.md        # durable user profile (gitignored; see *.example.md)
├── knowledge/**/*.md     # reusable reference context
├── eval/                 # benchmark runners and tasks
├── models/<name>/        # generated system.txt + Modelfile
├── Makefile              # make check: rebuild changed models, verify the stack
└── build-{gemma,qwen,lite}
```

Prompt assembly order is `knowledge/`, then `memory/`, then `prompts/`; files
within each directory are sorted. That keeps reference context first and behavior
rules last. Each Markdown file is wrapped in `--- START/END FILE ---`. Files over
100k are skipped, as are `*.example.md` templates — injecting a template beside
the real file would hand the model two conflicting profiles. Builders abort if the assembled prompt contains `"""`, because
that would break the Ollama `SYSTEM """..."""` block.

## Build And Tune

The only model-specific part of a builder is the top config block:

```bash
MODEL_NAME="qwen"
BASE_MODEL="qwen3.6:35b-a3b-mtp-q4_K_M"
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
| New prompt-stack rule check | `eval/persona_tasks.py` |

Keep prompt text terse. Every prompt token is spent every turn; prefer removing
bad rules or tuning `PARAMS` before adding more instructions. To find out *which*
rules are worth keeping, run
`./eval/run-persona.py --models gemma qwen lite --system-mode baseline` and
compare against a stacked run: a rule the base model already obeys unprompted is
costing tokens for nothing. See *Prompt Stack Value* below for the current
measured answer.

**After editing anything in `prompts/`, `memory/`, or `knowledge/`, rebuild and
run the persona suite** — it is the only suite that tests the stack itself rather
than the base model behind it. That used to be manual discipline; it is now a
target:

```bash
make check   # rebuild only the models whose stack changed, then run run-persona.py
make hook    # install a pre-commit hook that does the same on staged prompt edits
```

`make build` rebuilds without verifying, `make persona` verifies without
rebuilding, and `make clean` drops the stamps to force a full rebuild. Editing a
single `build-*` script rebuilds only that model; editing anything under
`prompts/`, `memory/`, or `knowledge/` rebuilds all three, because every builder
assembles the same stack.

## Ollama Server

Local service override:

```ini
# sudo systemctl edit ollama
[Service]
Environment="OLLAMA_KV_CACHE_TYPE=q4_0"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_KEEP_ALIVE=10m"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
```

`OLLAMA_MAX_LOADED_MODELS=1` matters for the benchmarks, not just for daily use.
At `2` the resident models compete for the same 10 GB, so a model's measured
throughput depends on which other model happens to be loaded beside it — the
leaderboard would be measuring co-residency, not the model. At `1` each model
gets the whole card in turn. `run-learn.py` and `run-tutor.py` are already built
for this: they generate every response first, then loop by judge, so each model
loads once per phase instead of thrashing on every call.

**Restarting the Ollama service invalidates a run in flight.** The runners now
preflight the server and abort on a streak of connection failures rather than
recording every attempt as a model failure — but an abort still costs you the
run. Let a `standard` pass finish before touching the unit file.

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
ollama run lite
```

## Use In VSCode (Continue / Cline)

Both extensions talk to Ollama's local API at `http://localhost:11434`. Build the
models first (`make build`) so the custom names resolve, then confirm they are
loaded with `ollama list`.

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
  - name: lite (fast baseline)
    provider: ollama
    model: lite
    roles: [chat, edit, apply]
```

Pick the default from the leaderboard above rather than from load size — that
guess is what the benchmark exists to replace. Continue auto-discovers Ollama,
but listing the custom names keeps the prompt-stacked builds (not the raw bases)
in the model picker.

### Cline

In Cline's settings, set **API Provider** to `Ollama`, **Base URL** to
`http://localhost:11434`, and **Model** to `qwen`, `gemma`, or `lite`. Cline is
agentic/coding-heavy and ingests large prompts, so prompt-eval throughput matters
more here than generation speed — `run-speed.py` reports both, and the
**Prompt tok/s** column is the one to drive this choice, not **Gen tok/s**.

Notes for both: keep `OLLAMA_KEEP_ALIVE` long enough to avoid reload churn when
switching models. `gemma` and `qwen` do not fit entirely in 10 GB of VRAM, so expect
CPU spill on both; both are MoE, which is what keeps that spill usable. `lite`
fits, and is the control for how much that spill actually costs.

## Evaluation

Runners live under `eval/` and write results to `eval/runs/<UTC>/`. Routine
testing goes through profiles (`smoke` after a rebuild, `standard` for the
under-1-hour comparison, `deep` for a several-hour confidence run — see
[`TESTING.md`](TESTING.md) for when to use each):

```bash
./eval/run-profile.py smoke --models gemma qwen lite
./eval/run-profile.py standard --models gemma qwen lite
```

Individual runners remain available for targeted sweeps:

```bash
./eval/run-speed.py --models gemma qwen lite
./eval/run-code.py --models gemma qwen lite
./eval/run-content.py --models gemma qwen lite
./eval/run-learn.py --models gemma qwen lite
./eval/run-tutor.py --models gemma qwen lite
./eval/run-json.py --models gemma qwen lite
./eval/run-persona.py --models gemma qwen lite
```

`run-persona.py` is the prompt-stack regression suite: it checks that the rules in
`prompts/`, `memory/`, and `knowledge/` are actually obeyed — the identity rule,
the `memory/user.md` honesty rules about Casey's skill buckets, `Unverified:`
marking, and output shape. Every other runner measures the base model *through*
the stack, so this is the only one that notices when a prompt edit breaks a rule.
Scoring is deterministic regex, no judge.

`run-json.py` is the structured-output test the consumer apps (Jobhunt,
SEO-LLM) depend on: it constrains decode with a JSON schema, buries facts in a
multi-thousand-token document, and scores schema conformance plus long-context
fact recall. It pins `num_ctx 32768` to match how those apps call Ollama.

`run-code.py`, `run-learn.py`, and `run-tutor.py` execute model-generated Python.
That execution is confined by **bubblewrap**: read-only `/usr`, no network, no
host PID/IPC namespace, no access to `$HOME`, and write access only to a
throwaway CWD. Each run prints the active mode in its banner, and degrades
loudly — not silently — to a bare timeout-bounded subprocess on a box without a
working `bwrap`. Full runner flags and the sandbox details are in
[`TESTING.md`](TESTING.md).

After a run, promote the numbers into the leaderboard below instead of copying
them by hand:

```bash
./eval/promote.py             # newest run per suite -> the table below
./eval/promote.py --check     # exit 1 if the table is stale
```

## Benchmark Leaderboard

Measured on the current lineup. This block is generated — `./eval/promote.py`
rewrites everything between the markers from `eval/runs/`, so it cannot drift
away from the runs the way the hand-maintained 2026-06-14 tables did (those
survived two base swaps still reading as current; see [`TESTING.md`](TESTING.md)
for that history). Treat small gaps as directional: failures are strong signal,
close wins are weak signal, and speed breaks quality ties.

<!-- BENCH:START -->

_Generated by `./eval/promote.py` from 7 runs, 20260728T215614Z–20260728T233628Z (`eval/runs/`). Do not hand-edit: re-run the script._

| Suite | Winner | `lite` | `qwen` | `gemma` |
|---|---|---|---|---|
| Speed | `lite` | 89.4, 100% GPU | 40.9, 75%/25% CPU/GPU | 28.3, 66%/34% CPU/GPU |
| Coding | `gemma` | 23/27 | 23/27 | 26/27 |
| Content | `gemma` | 7/9 | 8/9 | 9/9 |
| Learning | tie | 7.0, 9/12 | 9.9, 12/12 | 9.8, 12/12 |
| Tutor (leak-gated) | `gemma` | 5.3, 6/15 | 5.6, 6/15 | 9.5, 0/15 |
| JSON / long-context | tie | 100%, 1.9 | 100%, 7.2 | 100%, 6.0 |
| Prompt stack | `qwen` | 57% | 90% | 43% |

Winner is `tie` where the runner flagged the margin as within its close-result threshold — those rows should break on speed, not the headline metric. Per-suite run directories:

- Speed: `eval/runs/20260728T215614Z/speed/summary.md` — 89 tok/s (100% GPU, thinking OFF)
- Coding: `eval/runs/20260728T215725Z/code/summary.md` — 26/27 (96%) @ 31 tok/s
- Content: `eval/runs/20260728T220323Z/content/summary.md` — 9/9 clean (100%) @ 30 tok/s
- Learning: `eval/runs/20260728T221541Z/learn/summary.md` — teach 9.9/10 (code 12/12, explanation 9.9/10)
- Tutor (leak-gated): `eval/runs/20260728T223432Z/tutor/summary.md` — teach 9.5/10 (leaks 0/15, explanation 9.5/10, non-leak explanation 9.5/10)
- JSON / long-context: `eval/runs/20260728T221011Z/json/summary.md` — score 100% (schema 100%, facts 100%)
- Prompt stack: `eval/runs/20260728T233628Z/persona/summary.md` — 19/21 clean (90%)

<!-- BENCH:END -->

### Current picks

| Use | Pick | Basis |
|---|---|---|
| Fast local general use | `lite` | 89 tok/s at **100% GPU** — 2× `qwen`, 3× `gemma`, and the only model with no CPU spill. |
| Agentic tools (Cline) | `lite` | Prompt ingest is what matters when the tool ships large contexts: 9562 tok/s vs `gemma` 6465 and `qwen` 1563. |
| Coding | `gemma` | 26/27 vs 23/27 for both others. |
| Content / SEO / copy | `gemma` | 9/9 clean vs `qwen` 8/9, `lite` 7/9. |
| Socratic tutoring (no spoilers) | `gemma` | **0/15 leaks** vs 6/15 for both others — the one decisive gap in the whole run. Teach 9.5/10 vs 5.6 and 5.3. |
| Learning explanations | `qwen` / `gemma` (tie) | 9.9 vs 9.8, inside the tie threshold; both 12/12 on the code gate. `lite` trails on the gate (9/12), not on explanation quality. |
| Structured JSON / app smoke tests | `lite` | All three scored 100%; `lite` is ~3× faster end-to-end (1.9s vs 6.0/7.2s). |
| Prompt-stack fidelity | `qwen` | 90–95% clean vs `gemma` 43–57%. If you want the stack's rules actually obeyed, this is the model that obeys them. |

No single model wins. `gemma` takes the quality suites, `lite` takes everything
speed-shaped and is genuinely competitive on quality, `qwen` is the only one that
reliably follows the prompt stack. `lite` earning three rows is the result worth
noting — a 9B dense model that fits in VRAM was not expected to be the pick for
anything.

Two caveats before leaning hard on the small gaps. Samples are small (n = 9–27
per model), and `--seed` does not currently survive a process restart on this box
(see [`TESTING.md`](TESTING.md)), so run-to-run drift is real: `lite`'s
prompt-stack score read 62% and 57% on two runs of the same suite against builds
that differ only by a rule measured to change nothing. Failures and the leak-rate
gap are strong signal; a few points either way is not.

## Prompt Stack Value

What each rule actually buys, measured 2026-07-28: `run-persona.py` stacked vs
`--system-mode baseline`, 3 attempts × 3 models, so each rule scores out of 9.

| Rule | Stacked | Baseline | Buys | Read |
|---|---:|---:|---:|---|
| `identity` | 9/9 | 0/9 | **+9** | Load-bearing. Without it every base volunteers a developer and training origin. |
| `model_origin` | 7/9 | 0/9 | **+7** | Load-bearing, same reason. |
| `familiar_skill` | 5/9 | 1/9 | **+4** | Load-bearing but leaky — no model holds it 3/3. The honesty rule most worth rewriting. |
| `unknown_fact` | 6/9 | 3/9 | **+3** | Load-bearing on `qwen`/`lite`. `gemma`'s clean baseline is an artifact: with no profile it has never heard of Casey, so it declines for the wrong reason. |
| `unverified` | 3/9 | 0/9 | **+3** | Works on `qwen` only; 0/3 on `gemma` and `lite` **stacked as well as unstacked**. See the negative result in [`TESTING.md`](TESTING.md) — rewriting it did not fix this. |
| `fields_echo` | 3/9 | 0/9 | **+3** | Same shape: `qwen` 3/3, the other two 0/3 stacked. |
| `bash_block` | 9/9 | 9/9 | **0** | Free. **Rule deleted 2026-07-28** — all three bases already fence commands in `bash` with no `$` prefix unprompted. |

Only `bash_block` was cut: it is the one rule confirmed at zero contribution
twice, on two different lineups. The deletion was verified with `make check` —
`bash_block` still scores 3/3 on all three models with the rule gone.

The honest caveat on the rest: `unverified` and `fields_echo` are not earning
their tokens on two of three models, but they are not *free* either — deleting
them would cost `qwen` a rule it does obey. They are candidates for a rewrite,
not a cut, and a rewrite has to be measured against a task that does not share
its subject with any example in the stack (that mistake is documented in
[`TESTING.md`](TESTING.md)).

## Models Tested

Full roster (current and retired). See [`TESTING.md`](TESTING.md) for the reasoning:

| Model | Base | Status |
|---|---|---|
| `gemma` | `gemma4:26b-a4b-it-qat` | current — rebuilt 2026-07-28 |
| `qwen` | `qwen3.6:35b-a3b-mtp-q4_K_M` | current — rebuilt 2026-07-28 |
| `lite` | `qwen3.5:9b` | current — added 2026-07-28 as the in-VRAM speed anchor and 3rd judge |
| `qwen` (uncensored) | `hf.co/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q4_K_M` | reverted 2026-07-28 — never benchmarked; works against `prompts/safety.md` by construction, so the shared stack spent tokens every turn fighting the base's own tuning. An uncensored base needs its own tag and its own stack, not a swap under the shared one. |
| `gemma` (prior) | `gemma4:12b-it-q4_K_M` | retired 2026-07-27 — base no longer installed; source of the 2026-06-14 scores |
| `gemma-custom` | `gemma4:e4b` | removed — superseded by gemma4 12B |
| `granite-custom` | `granite4.1:8b-Q5_K_M` | dropped — strong prior coding, no longer leads |
| `qwen-custom` | `qwen3.5:9b` | superseded 2026-06 by Qwen3.6 MoE; the base returned 2026-07-28 as `lite` |
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
