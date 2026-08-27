# Working example — evaluating the `catalogue` agent

A complete, runnable rook evaluation. The agent under test is
[`agent/catalogue.sh`](agent/catalogue.sh): a dependency-free library-loans CLI
with real state, so the whole thing is reproducible and costs nothing on the
agent's side. Only rook's own phases (`explore`, `generate`, `run`) consume
credits.

## What you need

- rook installed and signed in (`rook doctor`, `rook plan`)
- bash — already present on macOS and Linux; on Windows use Git Bash
- nothing else

## Try the agent first

```bash
cd example
./agent/catalogue.sh search "Le Guin"
./agent/catalogue.sh borrow b-1
./agent/catalogue.sh borrow b-1      # refused, exit 1
./agent/catalogue.sh status
./agent/catalogue.sh reset
```

It is specified in [`agent/CATALOGUE.md`](agent/CATALOGUE.md) — that file is
what `rook explore` reads to derive features, so the quality of the features
depends on it.

The behaviour is deliberately shaped to give rook something worth testing:
a happy path, refusals that must change nothing, and a **borrow limit of 2**
as a boundary.

## Try the transport

[`transport.sh`](transport.sh) is what rook actually invokes. Confirm it works
before involving rook:

```bash
./agent/catalogue.sh reset
./transport.sh 'catalogue borrow b-1'    # happy path
./transport.sh 'catalogue borrow b-1'    # refusal — note it still exits 0
./transport.sh 'Say hello'               # the prose handshake
```

The refusal is the interesting one:

```
refused: b-1 is already on loan — nothing changed

===== OBSERVED STATE (added by the transport, not by the agent) =====
goal_exit_code: 1

--- changed by this goal ---
NO CHANGE: the goal altered no loan state.
```

The agent exited 1, but the transport exits 0 and reports the real status
in-band. **This is not cosmetic.** rook discards stdout when the process exits
non-zero, so without it every refusal scenario would reach the judge as an
empty response and be graded "agent never ran" — losing exactly the evidence a
negative scenario exists to check. The `NO CHANGE` line is what lets a judge
verify "nothing was borrowed", which the agent's own output never states.

## Run the evaluation

```bash
# 1. Sign in and select a project
rook login
rook project use <ULID>          # or: rook project create catalogue-eval

# 2. Derive features from CATALOGUE.md
rook explore example/agent

# 3. Register the transport — BEFORE generate. Absolute paths.
rook profile add catalogue \
  --command "/bin/bash $(pwd)/transport.sh {{goal}}"
#   Windows: --command 'D:\Git\bin\bash.exe /c/path/to/transport.sh {{goal}}'

rook profile test catalogue      # must say "verified"

# 4. Write scenarios, now that the profile exists
rook generate -- "Each goal is ONE catalogue.sh command. Single turn. \
Assert on stdout and on the OBSERVED STATE block the transport appends."

# 5. Free check — do this before spending anything
rook scenarios list              # expect: N runnable against catalogue

# 6. Run and read
rook run --concurrency 1 --profile catalogue -- "The transport appends an \
OBSERVED STATE block: goal_exit_code, the full catalogue with each book's loan \
state, and a diff of what changed. Treat loan state as observable."

rook report
rook ui --local
```

Reset loan state between runs so scenarios start from a known point:

```bash
./agent/catalogue.sh reset
```

## What to expect

`rook explore` should find one agent and features along the lines of *search*,
*borrow*, *return* and *status*. `rook generate` will write functional scenarios
for the happy paths and adversarial ones around the refusals and the borrow
limit — the boundary at 2 is the most interesting thing in the spec.

`rook scenarios list` is the checkpoint that matters. If it reports
`0 runnable`, **stop and fix that first** — running would pay for the planning
phase and produce nothing but skips.

## Ordering matters

Register the profile **before** `generate`. rook's own guide lists them the
other way round, but generating with no profile present makes the planner assume
a richer agent than a single-shot command — multi-turn conversation, observable
tool calls — and those scenarios can never run. No amount of editing the profile
fixes it afterwards, because the assumptions are baked into the scenarios.

If that has already happened, `rook generate --force` with the profile active
rewrites them.
