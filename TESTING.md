# Testing

This is the source of truth for how this repo evaluates local Ollama models:
runner usage, safety notes, current benchmark results, and historical testing
decisions. `README.md` only carries the operational summary and compact
leaderboards.

## Goals

The suite answers three practical questions:

1. **Can the model follow content instructions?** Format discipline, SEO keyword
   control, length, and Markdown structure.
2. **Can the model write correct code?** Pass@1 on small self-contained Python
   tasks with hidden asserts.
3. **Can the model teach without leaking?** Explanation quality, code gate, and
   solution-leak checks for tutor use.

Speed is tracked separately because a better model that is too slow is not a
usable local default.

## Safety

`run-code.py`, `run-learn.py`, and `run-tutor.py` execute model-generated Python
in a subprocess with a fresh temp working directory and wall-clock timeout. They
are **not containerized**. Run trusted local models only.

Do not point the execution runners at newly-pulled community models without
reviewing the risk.

## Runner Matrix

All runners write to `eval/runs/<UTC>/`.

| Runner | Measures | Executes model code? | Default attempts | Confidence |
|---|---|---:|---:|---|
| `run-speed.py` | Raw generation tok/s, prompt tok/s, load time, GPU/CPU split | no | 1 per prompt | High for this machine |
| `run-content.py` | Format/instruction compliance across content tasks (SEO copy, technical explanation, Markdown brief) | no | 5 | Medium-high for prompt discipline |
| `run-code.py` | Real pass@1 against hidden Python asserts | yes | 5 per task | Medium-high for the covered task shapes |
| `run-learn.py` | Code + explanation, leave-one-out judge panel | yes | 3 per task | Medium because explanation quality is judge-scored |
| `run-tutor.py` | Leak-gated tutoring guidance | yes | 3 per task | Medium because leak checks are strong but teaching quality is judge-scored |
| `run-json.py` | Schema-constrained JSON + long-context fact recall | no | 3 per task | Medium for structured-output reliability at the tested context sizes |

Common flags:

```bash
--models NAME
--attempts TIMES
--timeout SECONDS
```

Runner-specific flags:

| Runner | Extra flags |
|---|---|
| `run-speed.py` | `--num-predict N`, `--thinking auto|on|off`, `--opt KEY=VAL` |
| `run-code.py` | `--tasks ...`, `--exec-timeout SECONDS`, `--thinking auto|on|off` |
| `run-content.py` | `--tasks ...`, `--prompt-file PATH` (ad-hoc SEO prompt), `--keyword TEXT`, `--thinking auto|on|off` |
| `run-learn.py` | `--tasks ...`, `--judges ...`, `--judge-rubric default|strict`, `--exec-timeout SECONDS`, `--thinking auto|on|off` |
| `run-tutor.py` | `--tasks ...`, `--judges ...`, `--judge-rubric default|strict`, `--exec-timeout SECONDS`, `--thinking auto|on|off` |
| `run-json.py` | `--tasks ...`, `--num-ctx N` (default 32768), `--context-pressure normal|medium|high`, `--position default|early|middle|late|all`, `--thinking auto|on|off` |

Thinking mode can be forced with `--thinking on`, disabled with `--thinking off`,
or selected per model by appending `:think` to the model spec. Do not use
thinking mode for content runs unless explicitly testing it.

`run-json.py --context-pressure` scales document length to probe true
long-context degradation: `normal` (default) is the standard ~6-7k-token
prompts, `medium` lands ~15-19k, and `high` ~21-27k — as close to the 32k
`num_ctx` pin as fits without truncation. `--position early|middle|late|all`
moves the buried needle to measure position bias. Both are manual sweeps, not
part of the default comparison. `--judge-rubric strict` on the learn/tutor
runners pushes judges to reserve top marks when default grading saturates.

## Interpreting Results

These tests are for personal model selection on this workstation, not broad
public claims about model quality. Treat failures as strong signal: a model that
misses schema, leaks a full tutoring solution, or fails hidden asserts is risky
for that use. Treat small wins as weak signal until repeated: a one-attempt or
one-task edge can be noise. When quality is tied or close enough to be unclear,
break ties by speed, load behavior, and GPU residency.

Every summary now reports its own uncertainty: a 95% Wilson confidence interval
on the headline rate, a small-sample flag below 10 attempts, the weakest task
per model, and a close-result warning when the winner's margin is within the tie
threshold (5 points for rates, 0.5/10 for judge scores). Learn/tutor summaries
add a judge-reliability section (parse rate, inter-judge disagreement, and a
warning when a response was scored by fewer than two judges — with the current
2-model lineup, leave-one-out always leaves a single judge, so those /10 scores
are soft signal until a third model joins the panel). Tutor ranking breaks
teach-score ties on leak rate: the model that leaks less wins.

Confidence by signal:

| Signal | Confidence | How to use it |
|---|---|---|
| Speed, load time, GPU/CPU split | High | Directly measured on this machine. |
| Code pass/fail | Medium-high | Real execution against hidden asserts, scoped to these tasks. |
| JSON schema + fact checks | Medium | Good structured-output smoke test, but still a small task set. |
| Content compliance | Medium-high | Useful for the project prompts, not a general writing benchmark. |
| Learning explanation score | Medium | Leave-one-out judging reduces self-bias, but judges are still models. |
| Tutor score | Medium | Leak failures are strong. Teaching scores are judge-sensitive. |


## Benchmark Profiles

`./eval/run-profile.py` is the standard way to run comparisons; it wraps the
individual runners so routine testing doesn't drift across hand-typed flags.

```bash
./eval/run-profile.py smoke --models gemma qwen      # after a model rebuild
./eval/run-profile.py standard --models gemma qwen   # routine full comparison
./eval/run-profile.py deep --models gemma qwen       # pre-decision confidence run
./eval/run-profile.py standard --models gemma qwen --dry-run  # show commands
```

| Profile | When to run | Runtime | What it does |
|---|---|---|---|
| `smoke` | After every `build-*` rebuild or runner change | ~5-10 min | Speed (capped output) + 2 coding tasks + SEO content + 1 JSON task, 2 attempts each |
| `standard` | When picking models or after prompt-stack changes | under 1 hour | All six suites; code/content trimmed to 3 attempts so the expanded task set stays in budget |
| `deep` | Before trusting a close call or promoting a new model | several hours | Full 5-attempt sweeps plus medium and high context-pressure JSON runs |

The wrapper prints every `summary.md` it produced at the end. Individual runners
remain usable directly for targeted sweeps (single task, context pressure,
needle position, strict rubric).

Add tasks in:

| Task type | File |
|---|---|
| Coding correctness | `eval/coding_tasks.py` |
| Content compliance | `eval/content_tasks.py` |
| Code + learning explanation | `eval/learning_tasks.py` |
| Leak-gated tutoring | `eval/tutor_tasks.py` |
| Schema/long-context extraction | `eval/json_tasks.py` |

## Current Benchmark Snapshot

Latest full head-to-head: `gemma` (`gemma4:12b-it-q4_K_M`) vs `qwen`
(`qwen3.6:35b-a3b-mtp-q4_K_M`) on 2026-06-14, a full `standard` pass across all
six suites (3 attempts/task). The run artifacts are present under `eval/runs/`
and linked per suite below.

Two caveats on reading the tables. First, samples are small (n = 9–27 per
model): several suites carry a "tied within threshold" flag and wide Wilson
intervals, so treat one-task or sub-5-point edges as noise. Second, the
learn/tutor /10 scores rest on a 2-model leave-one-out panel — a single judge
per response — so they are soft signal until a third judge model joins. Where
quality ties, the tables break on speed and GPU residency, which favor `gemma`.

### Speed (`run-speed.py`)

Run: `eval/runs/20260614T200816Z/speed/summary.md`

| Rank | Model | Think | Gen tok/s | Prompt tok/s | Load | Size | GPU/CPU split |
|---|---|---|---:|---:|---:|---:|---|
| 1 | `gemma` | off | 54.0 | 17562 | 11.5s | 7.7 GB | 100% GPU |
| 2 | `qwen` | off | 46.7 | 1680 | 13.2s | 29 GB | 74%/26% CPU/GPU |

Finding: Gemma is the fast local default. The widest gap is in prompt ingestion —
17.6k vs 1.7k tok/s (~10×) — which is why Gemma also wins end-to-end latency on
the JSON and content suites. Qwen remains usable despite heavy CPU spill.

### Coding (`run-code.py`)

Run: `eval/runs/20260614T200906Z/code/summary.md`

| Rank | Model | Pass rate | Passed | Avg s | Tok/s |
|---|---|---:|---:|---:|---:|
| 1 | `qwen` | 96% | 26/27 | 3.8 | 59 |
| 2 | `gemma` | 96% | 26/27 | 4.1 | 54 |

Per task (passed / 3):

| Model | two_sum | valid_parentheses | merge_intervals | lru_cache | edit_distance | calc | decode_string | coin_change | flatten_dict |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `qwen` | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 |
| `gemma` | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 2/3 | 3/3 | 3/3 | 3/3 |

Finding: Dead tie at 26/27, flagged within the tie threshold (was Qwen 30/30 vs
Gemma 29/30 on the smaller 6-task set). Each model dropped one attempt: Gemma on
`calc` (its repeatable operator-precedence weak spot), Qwen on `decode_string`.
With quality level, the tie-break on speed/GPU residency favors Gemma.

### Content (`run-content.py`)

Run: `eval/runs/20260614T201250Z/content/summary.md`

| Rank | Model | Clean rate | Clean | Avg s | Tok/s | Avg words |
|---|---|---:|---:|---:|---:|---:|
| 1 | `gemma` | 100% | 9/9 | 6.6 | 54 | 224 |
| 2 | `qwen` | 78% | 7/9 | 11.7 | 33 | 227 |

Per task (clean / 3):

| Model | seo_product | tech_explain | md_brief |
|---|---:|---:|---:|
| `gemma` | 3/3 | 3/3 | 3/3 |
| `qwen` | 3/3 | 1/3 | 3/3 |

Finding: Gemma sweeps 9/9 and is ~2× faster (6.6s vs 11.7s, fully on GPU). Qwen
regressed on the expanded set, missing `tech_explain` 2/3 on format/instruction
rules. Gemma keeps the content/SEO pick decisively.

### Learning (`run-learn.py`)

Run: `eval/runs/20260614T201857Z/learn/summary.md`

| Rank | Model | Teach /10 | Code pass | Explanation /10 | Expl. when correct |
|---|---|---:|---:|---:|---:|
| 1 | `gemma` | 9.7 | 12/12 | 9.7 | 9.7 |
| 2 | `qwen` | 9.2 | 11/12 | 10.0 | 10.0 |

Finding: Flipped from the prior pass (Qwen 9.9 vs Gemma 9.4), but within the
0.5/10 tie threshold. Qwen still writes the better explanation (10.0 vs 9.7); it
lost the top spot only because it dropped a code gate (11/12). Single-judge
panel — read as soft signal and effectively a tie.

### Tutor (`run-tutor.py`, leak-gated)

Run: `eval/runs/20260614T202725Z/tutor/summary.md`

| Rank | Model | Teach /10 | Leaks | Explanation /10 | Explanation (no leaks) /10 |
|---|---|---:|---:|---:|---:|
| 1 | `gemma` | 6.9 | 3/15 | 8.5 | 8.6 |
| 2 | `qwen` | 3.8 | 9/15 | 9.3 | 9.5 |

Finding: The decisive split, and it widened. Qwen still explains better when it
does not leak (9.5 vs 8.6), but it now gives away the full solution 9/15 (60%) of
the time versus Gemma's 3/15, and the gate zeroes those attempts. Gemma is the
clear leak-gated tutoring pick.

### JSON / long-context (`run-json.py`)

Run: `eval/runs/20260614T201535Z/json/summary.md`

| Rank | Model | Score | Valid JSON | Schema OK | Fact rate | Avg s | Tok/s |
|---|---|---:|---:|---:|---:|---:|---:|
| 1 | `gemma` | 100% | 100% | 100% | 100% | 2.9 | 50 |
| 2 | `qwen` | 100% | 100% | 100% | 100% | 6.7 | 48 |

Per task: both models scored 3/3 on all seven tasks (`jd_extract`,
`needle_recall`, `decline_guard`, `conflicting_correction`, `enum_classify`,
`multi_extract`, `no_infer`).

Finding: both clear the structured-output suite at 100% (schema and facts) on the
expanded 7-task set. Tied on quality, Gemma wins end-to-end latency (2.9s vs
6.7s) on the strength of its prompt-ingest speed, so it stays the JSON default.

## Current Picks

| Use | Pick | Basis |
|---|---|---|
| Fast local default | `gemma` | 54 tok/s, 100% GPU; ~10× Qwen's prompt-ingest speed. |
| Content / SEO / copy | `gemma` | 9/9 clean vs Qwen 7/9, ~2× faster. |
| Structured JSON / consumer-app smoke tests | `gemma` | Tied Qwen at 100%, ~2× faster latency (2.9s vs 6.7s). |
| Coding puzzles / small functions | `gemma` / `qwen` (tie) | Tied 26/27; break on speed/GPU → Gemma. Gemma's only miss is `calc`. |
| Learning explanations | `gemma` / `qwen` (tie) | Gemma 9.7 vs Qwen 9.2 (within threshold); Qwen explains better but dropped a code gate. |
| Leak-gated tutoring | `gemma` | 6.9/10 with 3/15 leaks vs Qwen's 3.8 with 9/15. |

## Hardware

Benchmarks are for this local machine:

| Component | Value |
|---|---|
| GPU | RTX 3080, 10 GB VRAM |
| CPU | Ryzen 5900x |
| RAM | 32 GB DDR4-3600 |
| Ollama | 0.30-era testing for current Qwen/Gemma runs |

Models that fit 100% on GPU are fast. Dense spillover usually collapses
generation speed because DDR4 bandwidth becomes the bottleneck. MoE spillover is
less punishing because only a subset of parameters is active per token.

## Models Tested

| Model | Status | Notes |
|---|---|---|
| `gemma` (`gemma4:12b-it-q4_K_M`) | current | Wins or ties all six suites on 2026-06-14; fully on GPU, best content compliance, lowest latency. |
| `qwen` (`qwen3.6:35b-a3b-mtp-q4_K_M`) | current | Ties coding/JSON and explains well, but regressed on content and leaks 60% in leak-gated tutoring; heavy CPU spill. |
| `granite` (`granite4.1:8b-Q5_K_M`) | dropped | Strong prior coding runs, but no longer leads the current lineup. |
| `qwen-custom` (`qwen3.5:9b`) | removed | Fast 9B-era thinking model; superseded by current Qwen3.6 MoE results. |
| `ministral-custom` | removed | Strong historical #2; removed after Gemma/Granite consolidation. |
| `llama-custom` | removed | Last or near-last in early content/coding/teaching runs. |
| `qwen-big` / `qwen-moe` experiments | promoted/retired variants | Established that MoE can survive spillover; current `qwen` is the promoted MTP MoE line. |
| `gemma-big` | retired | Larger dense Gemma lost quality/speed tradeoffs on this hardware. |

## Historical Notes

The notes below are retained for decision history. Prefer the current snapshot
above when choosing a model today.

### Archived model-selection decision (2026-05-31)

From the 2026-05-29 run, the project first consolidated a larger model field
into purpose-built content/coding/tutor roles:

| Role | Model | Basis |
|---|---|---|
| Content generation | `gemma-content` | 5/5 clean at 180 tok/s. |
| Coding assistant | `granite-coder` | 27/30 pass@1 at 1.7 s/call. |
| Coding tutor | `granite-tutor` | Frontrunner teaching score, final pick deferred. |

Early leaderboards:

| Suite | Winner | Result |
|---|---|---|
| Content | `gemma-content` | 5/5 clean, 180 tok/s. |
| Coding | `granite-coder` | 27/30. |
| Teaching | `granite-coder` | 9.9/10, code 12/12. |
| Speed | `qwen-custom` | 87.8 tok/s, 100% GPU. |

### Quant and context exploration (2026-06-02 to 2026-06-03)

Key outcomes:

- Gemma quant/context sweeps showed sliding-window attention makes high context
  cheap; Gemma stayed fully on GPU at large context in those rounds.
- Dense Qwen3.6 27B spillover was unusable at about 3 tok/s.
- Qwen3.6 MoE spillover was much more viable than dense spillover.
- Granite Q5 was a useful quality bump over Q4 in prior coding tests, but later
  current-lineup testing favored Gemma/Qwen.

### 3x3 role matrix (2026-06-03)

The repo briefly expanded into content/coder/tutor variants across Gemma,
Granite, and Qwen families. Results:

| Role suite | Winner | Result |
|---|---|---|
| Content | `gemma-content` | 4/5 clean, 99 tok/s. |
| Coding | `gemma-coder` | 28/30, 104 tok/s. |
| Tutor | `qwen-tutor:think` | 9.0/10, 1/15 leaks. |

Decision at that point: Gemma for all three roles, mainly because it was fast,
clean, and avoided model reload churn.

### Qwen3.6 MoE promotion (2026-06-03 to 2026-06-06)

The MTP MoE line proved viable despite heavy CPU spill. Earlier speed sweeps put
it around the low-30 tok/s band thinking-off, with later runs showing stronger
coding and tutor behavior. It was promoted into the current `qwen` slot for
reasoning/coding comparison against Gemma.

### Head-to-head update (2026-06-07)

This completed Gemma/Qwen run changed the practical split:

- Gemma remains the fast content model.
- Qwen is now the clear coding and learning model in the local lineup.
- Leak-gated tutor status still needed a current rerun (done 2026-06-09).

### Head-to-head update (2026-06-09)

Full five-suite rerun:

- Speed: Gemma 58.3 tok/s (100% GPU) vs Qwen 40.6 tok/s (75%/25% CPU/GPU).
- Coding: Qwen still 30/30; Gemma improved to 29/30 (`calc` 4/5, up from 2/5).
- Content: both now 5/5 clean; Gemma keeps the pick on speed.
- Learning: Qwen 9.9 vs Gemma 9.4, both code 12/12.
- Tutor (leak-gated, finally rerun): Gemma 8.0/10 with 2/15 leaks beats Qwen
  5.9/10 with 6/15 leaks. Qwen explains better when it does not leak but fails
  the gate more often, so Gemma is the tutoring pick.

### Head-to-head update (2026-06-14)

First full `standard` pass on the expanded task set (coding 9, content 3, JSON 7)
with run artifacts retained under `eval/runs/`:

- Speed: Gemma 54.0 tok/s (100% GPU) vs Qwen 46.7 (74%/26% CPU/GPU); Gemma's
  prompt ingest ~10× Qwen's.
- Coding: now a tie at 26/27 each (was Qwen 30/30 vs Gemma 29/30 on the 6-task
  set). Gemma misses `calc`, Qwen misses `decode_string`.
- Content: Gemma 9/9 vs Qwen 7/9 — Qwen regressed on `tech_explain`.
- JSON: both 100% on 7 tasks; Gemma ~2× faster latency.
- Learning: flipped to Gemma 9.7 vs Qwen 9.2 (within threshold) after Qwen
  dropped a code gate (11/12); Qwen still scores higher on raw explanation.
- Tutor: gap widened — Gemma 6.9/10 with 3/15 leaks vs Qwen 3.8/10 with 9/15.

Net: the coding and learning picks that previously went to Qwen are now ties at
best; Gemma wins or ties every suite and is the better hardware fit. Standing
caveats: small n and a single-judge learn/tutor panel.
