# Working example — evaluating the `catalogue` agent

A complete, runnable rook evaluation. The agent under test is
[`agent/catalogue.sh`](agent/catalogue.sh): a dependency-free library-loans CLI
with real state, so the whole thing is reproducible and costs nothing on the
agent's side. Only rook's own phases (`explore`, `generate`, `run`) consume
credits.

Every command below was run from a clean `git clone`. The outputs shown are
real.

## What you need

- rook installed and signed in — check with `rook doctor` and `rook plan`
- bash — already on macOS and Linux; on Windows use Git Bash
- nothing else

---

## 1. The agent

```bash
cd example
./agent/catalogue.sh search "Le Guin"
```
```
b-1  The Left Hand of Darkness — Ursula K. Le Guin  [available]
b-3  The Dispossessed — Ursula K. Le Guin  [available]
```

```bash
./agent/catalogue.sh borrow b-1
```
```
borrowed b-1 — The Left Hand of Darkness
```

Refusals leave state untouched and exit 1:

```bash
./agent/catalogue.sh borrow b-1        # already on loan
```
```
refused: b-1 is already on loan — nothing changed        # exit 1
```

```bash
./agent/catalogue.sh borrow b-999      # refused: no such book       (exit 1)
./agent/catalogue.sh return b-1        # returned b-1 — The Left Hand of Darkness
./agent/catalogue.sh status            # id|title|author|state, one per line
./agent/catalogue.sh reset             # all loans cleared
```

The borrow limit is 2, and it is the most interesting thing to test:

```bash
./agent/catalogue.sh reset
./agent/catalogue.sh borrow b-1
./agent/catalogue.sh borrow b-2
./agent/catalogue.sh borrow b-3
```
```
refused: borrow limit of 2 reached — return something first        # exit 1
```

The agent is specified in [`agent/CATALOGUE.md`](agent/CATALOGUE.md). That file
is what `rook explore` reads to derive features, so the quality of the features
depends on it.

---

## 2. The transport

[`transport.sh`](transport.sh) is what rook actually invokes. Check it before
involving rook — it costs nothing.

```bash
./agent/catalogue.sh reset
./transport.sh 'catalogue borrow b-1'
```
```
borrowed b-1 — The Left Hand of Darkness

===== OBSERVED STATE (added by the transport, not by the agent) =====
goal_exit_code: 0

--- catalogue after the goal ---
b-1|The Left Hand of Darkness|Ursula K. Le Guin|on loan
b-2|Piranesi|Susanna Clarke|available
...

--- changed by this goal ---
BEFORE:  b-1|The Left Hand of Darkness|Ursula K. Le Guin|available
AFTER:   b-1|The Left Hand of Darkness|Ursula K. Le Guin|on loan
```

Now the important one — a refusal:

```bash
./transport.sh 'catalogue borrow b-1'    # already on loan
```
```
refused: b-1 is already on loan — nothing changed

===== OBSERVED STATE (added by the transport, not by the agent) =====
goal_exit_code: 1

--- changed by this goal ---
NO CHANGE: the goal altered no loan state.
```
```bash
echo $?    # 0 — the TRANSPORT succeeded even though the goal was refused
```

**The agent exited 1; the transport exits 0.** rook discards stdout when the
process exits non-zero, so without this every refusal scenario would reach the
judge as an empty response and be graded "agent never ran" — losing exactly the
evidence a negative scenario exists to check. The real status is reported
in-band as `goal_exit_code`, which a criterion can assert on.

`NO CHANGE` is what makes *"nothing was borrowed"* verifiable at all; the
agent's own output never states it.

And the handshake rook uses to verify a profile:

```bash
./transport.sh 'Say hello'
```
```
catalogue transport ready; goal was not a catalogue command: Say hello
```

---

## 3. Select a project — before anything else

```bash
rook login                       # if not already signed in
rook project                     # list selectable projects
rook project use <ULID>
```

`rook profile add` refuses without one:

```
no project selected — run `rook project <id>`
```

> Note the CLI's hint is wrong — the command is `rook project use <id>`, not
> `rook project <id>`.

---

## 4. Derive features from the spec

```bash
rook explore example/agent
rook agent use <agent-id>        # only if it finds more than one
```

Costs credits. Expect features along the lines of *search*, *borrow*, *return*
and *status*.

---

## 5. Register the transport — BEFORE `generate`

Absolute paths only: rook spawns argv with no shell.

```bash
# macOS / Linux
rook profile add catalogue --command "/bin/bash $(pwd)/transport.sh {{goal}}"

# Windows (Git Bash) — bash.exe lives in Git\bin, which is usually NOT on PATH
# Double quotes are deliberate: they keep the backslashes literal AND let
# $(pwd) expand as you type. Do not paste a made-up path here - an
# unsubstituted one is stored verbatim and fails later with exit 127.
rook profile add catalogue \
  --command "D:\Git\bin\bash.exe $(pwd)/transport.sh {{goal}}"
```

Verify it answers:

```bash
rook profile test catalogue
```
```
catalogue: answered in 257ms — verified
  catalogue transport ready; goal was not a catalogue command: Say hello and nothing else.
  rook profile use catalogue    to make it active
```

```bash
rook profile use catalogue       # make it active
rook profile show catalogue      # what it sends, references unexpanded
```

A profile that does not answer is saved **unverified** and cannot be used.

---

## 6. Write scenarios

```bash
rook generate -- "Each goal is ONE catalogue.sh command. Single turn. \
Assert on stdout and on the OBSERVED STATE block the transport appends."
```

Costs credits. The trailing instruction is how you tell the planner what the
transport can actually do — it is the cheapest lever available.

---

## 7. Check runnability — free, and do it every time

```bash
rook scenarios list
```
```
N scenario(s) · N runnable against catalogue
```

**If this says `0 runnable`, stop.** Running would pay for the planning phase
and produce nothing but skips. Fix the profile or regenerate first:

```bash
rook generate --force -- "..."       # rewrite with the profile active
rook scenarios exclude SC-001        # or drop specific ones
```

---

## 8. Run

```bash
./agent/catalogue.sh reset           # known starting state

rook run --concurrency 1 --profile catalogue -- "The transport appends an \
OBSERVED STATE block: goal_exit_code, the full catalogue with each book's loan \
state, and a diff of what changed. Treat loan state as observable."
```

Useful variants:

```bash
rook run --only SC-001,SC-002
rook run --class adversarial
rook run --test                      # keep out of the project timeline
```

---

## 9. Read the results

```bash
rook report                          # newest run — free
rook report <RUN_ID>
rook ui --local                      # browser viewer, works offline
rook status
```

Per-scenario evidence on disk:

```
.testmuai/rook/projects/<PROJECT>/agents/<AGENT>/runs/<RUN_ID>/
├── run.yaml      included/skipped per scenario, with the planner's reason
├── report.yaml   totals, credits, quality metrics
└── scenarios/<SC>/
    ├── request.json   exact goal sent
    ├── response.json  raw output, exit_code, latency
    └── verdict.yaml   per-criterion Pass/Fail with quoted evidence
```

Read `verdict.yaml` and `response.json` before reaching for `rook report --rca`.
They are free and factual; the RCA is a model's interpretation and costs credits.

---

## Ordering matters

Register the profile **before** `generate`. rook's own guide lists them the
other way round, but generating with no profile present makes the planner assume
a richer agent than a single-shot command — multi-turn conversation, observable
tool calls — and those scenarios can never run. No amount of editing the profile
fixes it afterwards, because the assumptions are baked into the scenarios.

## If sync or a normal run fails

If `rook project use <id>` rejects a project you just created with
`rook project create`, that project was never persisted upstream. The symptoms
follow from that:

- `rook sync` → `could not record the sync`
- a normal `rook run` dies before invoking the agent — its run directory has
  no `report.yaml`, and no `request.json` under `scenarios/`

`rook run --test` still works, and produces full verdicts and evidence; it only
skips recording the run in the project timeline. Use it to keep working, and
select a project that `rook project use` actually accepts before relying on
`sync`.
