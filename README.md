# rook — local evaluation guide

**rook tests an AI agent you own.** It reads your codebase to work out what the
agent does, writes test scenarios for it, runs them against the live agent, and
grades what comes back.

It is not a unit-test runner. The thing under test is an *agent* — something
that takes a goal in and produces behaviour out — and the grading is done by a
model reading the agent's actual response against per-scenario acceptance
criteria, producing a written verdict you can read a month later.

Everything lands on disk as plain YAML and JSON you can diff and edit.

---

## Start here: a runnable example

[`example/`](example/) is a complete evaluation you can actually run. The agent
under test is [`catalogue.sh`](example/agent/catalogue.sh) — a dependency-free
library-loans CLI with real state, so nothing but rook's own phases costs
anything.

Every command below was run from a clean `git clone`; the output shown is real.

### 1. Talk to the agent

```bash
git clone https://github.com/lambdapro/rook-eval.git
cd rook-eval/example

./agent/catalogue.sh search "Le Guin"
```
```
b-1  The Left Hand of Darkness — Ursula K. Le Guin  [available]
b-3  The Dispossessed — Ursula K. Le Guin  [available]
```

```bash
./agent/catalogue.sh borrow b-1        # borrowed b-1 — The Left Hand of Darkness
./agent/catalogue.sh borrow b-1        # refused: already on loan       (exit 1)
./agent/catalogue.sh borrow b-999      # refused: no such book          (exit 1)
./agent/catalogue.sh status            # id|title|author|state, per line
./agent/catalogue.sh reset             # all loans cleared
```

The borrow limit is 2 — the boundary worth testing:

```bash
./agent/catalogue.sh reset
./agent/catalogue.sh borrow b-1
./agent/catalogue.sh borrow b-2
./agent/catalogue.sh borrow b-3
```
```
refused: borrow limit of 2 reached — return something first        # exit 1
```

### 2. Run the transport rook will call

```bash
./agent/catalogue.sh reset
./transport.sh 'catalogue borrow b-1'    # happy path
./transport.sh 'catalogue borrow b-1'    # refused — the interesting one
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

The agent exited 1; the transport exits 0. rook discards stdout on a non-zero
exit, so without this every refusal would reach the judge empty and be graded
"agent never ran". `NO CHANGE` is what makes *"nothing was borrowed"*
verifiable at all.

### 3. Wire it into rook

```bash
rook project use <ULID>            # required first — profile add refuses without it

rook explore example/agent         # derive features from CATALOGUE.md   [credits]

# absolute paths — rook spawns argv with no shell
rook profile add catalogue --command "/bin/bash $(pwd)/transport.sh {{goal}}"

# Windows: bash.exe lives in Git\bin, which is usually NOT on PATH
# Double quotes are deliberate: they keep the backslashes literal AND let
# $(pwd) expand as you type. Do not paste a made-up path here - an
# unsubstituted one is stored verbatim and fails later with exit 127.
rook profile add catalogue \
  --command "D:\Git\bin\bash.exe $(pwd)/transport.sh {{goal}}"

rook profile test catalogue
```
```
catalogue: answered in 257ms — verified
```

```bash
rook profile use catalogue
rook generate -- "Each goal is ONE catalogue.sh command. Single turn."  # [credits]
rook scenarios list                # FREE — stop here if it says 0 runnable
rook run --concurrency 1 --profile catalogue                           # [credits]
rook report                        # free
rook ui --local                    # browser viewer, works offline
```

**[`example/README.md`](example/README.md) has the complete flow** — every step
with its real output, and what to do when one fails.

The example exists to demonstrate the failure modes that actually bite:
refusals whose evidence would otherwise be discarded, state a judge cannot see
from command output alone, and the profile-before-generate ordering rule.

---

## What rook can do

| Phase | Command | What it produces |
|---|---|---|
| Discover | `rook explore [path]` | Finds agents in a codebase and writes **features** describing what each does |
| Author | `rook generate` | Writes **scenarios** — functional, non-functional and adversarial — with acceptance criteria |
| Connect | `rook profile add` | A **profile**: how to actually invoke the agent (a curl, or a command line) |
| Execute | `rook run` | Runs scenarios against the live agent and **judges** each response |
| Explain | `rook report [--rca]` | Totals, credits, quality metrics, failure clusters |
| Curate | `rook scenarios` | List / exclude / include / delete scenarios |
| Inspect | `rook ui --local` | Browser viewer for agents, features, scenarios, runs, evidence |
| Record | `rook sync` | Pushes the project upstream (the only thing that leaves your machine) |

Supporting commands: `rook login`, `rook auth status`, `rook whoami`, `rook plan`
(credits), `rook project`, `rook agent use`, `rook runs`, `rook status`,
`rook env`, `rook mcp`, `rook doctor`, `rook guide`, `rook docs`, `rook ask`.

**Scenario classes** — `functional`, `non_functional`, `adversarial`.
**Categories** — `happy_path`, `negative`, `boundary`, `integration`,
`state_context`, `performance`, `token_economy`, `reliability`, `quality`,
`prompt_injection`, `jailbreak`, `data_exfiltration`, `pii_leakage`,
`harmful_content`, `hallucination`, `hijacking`, `policy_violation`.

### What costs credits

`explore`, `generate`, `run` and `report --rca` call a model and are billed.
`status`, `scenarios list`, `report` (without `--rca`), `sync`, `ui` and
`doctor` read what is already on disk and are free. Check your balance with
`rook plan`.

---

## A successful local evaluation, start to finish

### 0. Verify the environment

```bash
rook --version
rook doctor        # version, node, workspace, controller + api reachability,
                   # identity, auth, project, mode, tty, state
rook plan          # username, organisation, credit balance
```

`rook doctor` is the fastest way to see whether the controller is reachable and
which project is selected. `state: offline` there means *unsynced*, not
disconnected — `rook status --json` reports the real `"offline"` boolean.

### 1. Sign in and pick a project

```bash
rook login                     # browser flow; needs a TTY
rook whoami

rook project                   # list selectable projects: <ULID>  <name>
rook project use 01J...        # select an existing one
rook project create catalogue-eval    # or make a new one, and select it
```

A project is required before almost anything else. Without one:

```
no project selected — run `rook project <id>`
```

> The hint is wrong — the command is `rook project use <id>`.

If `rook project use` later rejects a ULID that `create` just returned, that
project was never persisted upstream. See [Troubleshooting](#troubleshooting).

### 2. Point rook at the codebase

```bash
rook explore example/agent
rook explore example/agent -- "a library loans CLI specified in CATALOGUE.md"
```

This writes **features** — one per capability it finds — into
`.testmuai/rook/projects/<PROJECT>/agents/<AGENT>/features/`. Review them;
everything downstream is derived from them.

```bash
rook agent use catalogue       # only if it found more than one agent
```

#### If it finds nothing, the cache is stale

```
nothing on disk moved — no scan needed
0 analysed, 0 unchanged, 0.00 credits
```

`explore` hashes the tree into `.testmuai/rook/cache/__project__/index.json`
and skips the scan when nothing changed. That message is correct after a real
scan — but `0 analysed, 0 unchanged` is zero on *both* sides, which no
up-to-date scan ever reports. It means the file index was written without any
agent being derived, so every later `explore` short-circuits against it and
finds nothing.

Confirm it before spending credits — this is free:

```bash
ls .testmuai/rook/projects/<PROJECT>/agents/     # missing => nothing derived
```

If `agents/` is absent, clear the cache the supported way — re-derive
whatever the hashes say:

```bash
rook explore example/agent --force --verbose     # [credits]
```

`--verbose` prints each subagent call and the running credit total, so you can
watch `find_agents` actually fire instead of inferring it from a summary line.
Deleting `.testmuai/rook/cache/` by hand works too, but `--force` is scoped to
this path and leaves the rest of the project state alone.

A `--force` run may also decline a tool call it will not make unattended:

```
! bash(type example\agent\CATALOGUE.md) was chosen by a model,
  not asked for, and there is nobody to confirm it. Pass --allow 'bash(...)'
  to authorise it for this run.
```

It is not fatal — the run continues and reads the file another way. Only add
`--allow` if the same call keeps blocking real progress.

### 3. Describe how to reach the agent — DO THIS BEFORE `generate`

> **This is the single most important ordering rule.** rook's own guide lists
> `generate` as step 5 and `profile add` as step 6, but generating scenarios
> while no profile exists makes the planner assume a rich agent — multi-turn
> conversation, observable tool calls, file inputs. If your transport is a
> single-shot command, those scenarios can never run, and no amount of editing
> the profile fixes it because the assumptions are baked into the scenarios.

```bash
# A command line — {{goal}} is where each scenario's goal is substituted
rook profile add catalogue --command "/bin/bash $(pwd)/example/transport.sh {{goal}}"

# Windows: bash.exe lives in Git\bin, which is usually NOT on PATH
# Double quotes are deliberate: they keep the backslashes literal AND let
# $(pwd) expand as you type. Do not paste a made-up path here - an
# unsubstituted one is stored verbatim and fails later with exit 127.
rook profile add catalogue \
  --command "D:\Git\bin\bash.exe $(pwd)/transport.sh {{goal}}"

# Or from a curl (a file, or piped on stdin)
rook profile add catalogue --from ./request.curl
```

```bash
rook profile test catalogue    # MUST answer, or it stays unverified and unusable
```
```
catalogue: answered in 257ms — verified
  catalogue transport ready; goal was not a catalogue command: Say hello and nothing else.
  rook profile use catalogue    to make it active
```

```bash
rook profile use catalogue     # make it the active profile
rook profile show catalogue    # what it sends, references unexpanded
```

`--command` **must** contain `{{goal}}`, or rook refuses it:

```
--command has no {{goal}} — every scenario would send the same fixed call
```

Do not wrap `{{goal}}` in quotes. rook spawns argv directly with no shell, so it
already stays one token — quoting it passes literal quote characters to your
agent.

### 4. Write scenarios

```bash
rook generate
rook generate --total 20 --class functional,adversarial
rook generate --category boundary,negative,state_context

rook generate -- "Each goal is ONE catalogue.sh command. Single turn. Assert on \
stdout and on the OBSERVED STATE block the transport appends."

rook generate --force -- "..."    # rewrite everything, whatever the pins say
```

The trailing instruction after `--` is how you tell the planner what your
transport can actually do. It is the cheapest lever you have — far cheaper than
discovering at run time that nothing is runnable.

**Treat it as mandatory.** A bare `rook generate` against this example produced
16 scenarios of which **15 could not run** — every one asserting that a
`search`/`borrow`/`return` *tool call* occurred, which a single-shot CLI can
never expose:

```
cannot run: it asserts what search did and catalogue cannot observe tool calls
```

The ordering rule above was satisfied — the profile was active and verified
before `generate` ran. Ordering alone does not save you. The profile says how
the agent is reached; only the instruction says what its answers can show.

### 5. Check runnability — free, and do it every time

```bash
rook scenarios list
```
```
16 scenario(s) · 1 runnable against catalogue

✗ SC-001  Search catalogue books by author substring case-insensitively
    functional · happy_path · F-001 · 3 criteria
    cannot run: it asserts what search did and catalogue cannot observe tool calls
  SC-007  Search reflects on loan state after successful borrow operation
    functional · state_context · F-001 · 3 criteria
```

**If this says `0 runnable`, stop.** Running would pay for the planning phase and
produce nothing but skips.

```bash
rook scenarios exclude SC-004 SC-007    # keep on disk, leave out of runs
rook scenarios include SC-004
rook scenarios delete SC-007            # permanent
```

### 6. Run

```bash
./example/agent/catalogue.sh reset      # known starting state

rook run --concurrency 1 --profile catalogue
rook run --only SC-007
rook run --class adversarial --category negative,boundary
rook run --test                         # keep out of the project timeline

rook run --profile catalogue -- "The transport appends an OBSERVED STATE block: \
goal_exit_code, the full catalogue with each book's loan state, and a diff of \
what changed. Treat loan state as observable."
```

Useful flags: `--tag`, `--name`, `--resume <id>`, `--rca`, `--json`,
`--verbose`, `--allow 'bash(npm test)'`.

On a project that was never synced, `rook run` plans and then stops without
executing anything:

```
  the plan is at ...runs/01M12NWVMV4W51V0210ZG2VVWM/run.yaml
this agent has never been synced upstream
  rook sync          record it, then run
  rook run --test    or run locally, recording nothing
not synced
```

The plan was still written and the planning phase was still billed. `rook run
--test` completes the identical loop — execution, judging, verdicts, evidence —
and skips only the project-timeline entry.

Runnability is re-decided **on every run** by a model reading each scenario
against the profile. It cannot know anything your transport does that the profile
does not state — so say it in the trailing instruction.

### 7. Read the results

```bash
rook report                    # newest run — free
rook report 01M1...            # a specific run
rook report --rca              # explains failure clusters — costs credits
rook ui --local                # browser viewer, works fully offline
rook ui --local --no-open      # print the URL instead
rook status                    # where this machine stands
rook status --json             # machine-readable, incl. the real offline flag
```

`rook report` totals look like this:

```
1 of 1 executed · 0% passed of 1 decided
  0 passed · 1 failed
  0 could not be decided from the evidence
  15 could not run against this profile
  5.51 credits · 6.5s wall clock
  agent latency: 161ms median · 1 turns
```

Everything is also on disk:

```
.testmuai/rook/projects/<PROJECT>/agents/<AGENT>/
├── features/     F-001.yaml …           what the agent is meant to do
├── scenarios/    SC-001.yaml …          goal + acceptance criteria
├── profiles/     catalogue.yaml         how the agent is invoked
└── runs/<RUN_ID>/
    ├── run.yaml      included/skipped per scenario, with the planner's reason
    ├── report.yaml   totals, credits, quality metrics, failure clusters
    └── scenarios/SC-001/
        ├── request.json   exact goal sent
        ├── response.json  raw output, exit_code, latency, transcript
        └── verdict.yaml   per-criterion Pass/Fail with quoted evidence
```

A run directory with no `report.yaml` never finished. One whose `scenarios/`
holds no `request.json` never reached your agent at all.

**Read `verdict.yaml` and `response.json` before reaching for `--rca`.** They are
free and factual; the RCA is a model's interpretation, costs credits, and can be
wrong about a cause the raw files state plainly.

### 8. Record it upstream

```bash
rook sync                      # every agent, as one write
rook runs sync                 # push finished runs that still owe upstream
```
```
catalogue: 4 feature(s), 12 scenario(s)
```

Nothing leaves your machine until you do this. If it fails, see
[Troubleshooting](#troubleshooting) — and note that `rook run --test` keeps
working regardless, producing full verdicts and evidence locally.

---

## Writing a transport that works

Scenario `goal` fields are whatever `generate` decided they should be — often a
literal command. The profile's job is to turn a goal into a real invocation and
return text the judge can grade. Four rules earn their keep:

**Return evidence even on failure.** rook discards stdout when the process exits
non-zero, so a failing command yields an empty response and an
`agent_never_ran` verdict. Exit 0 once the goal has actually run, and report the
real status in-band instead:

```
goal_exit_code: 1
```

**Pin your interpreters.** If `node`, `python` or the agent binary resolves via
a per-shell or version-manager shim, a run can inherit a path that no longer
exists and die with exit 127 *after* producing output. Use absolute paths.

**Expose state the criteria need.** Many scenarios assert durable facts —
"nothing was created", "the item is not yet trusted" — that command output alone
cannot show. Snapshot the relevant state before and after the goal and append it
under a clear heading, then tell the planner it exists via the `rook run`
instruction.

**Match the goals `generate` actually emits.** A transport that guards against
non-command input — so the `profile test` prose probe gets an answer — must let
real goals through that same guard. This example matched only a `catalogue ...`
prefix while `generate` wrote bare subcommands like `search Left Hand`, so every
goal fell into the probe branch and the agent was never invoked. Nothing looked
broken: the transport exited 0 and returned a fluent sentence, so the judge
graded the *reply* and reported

```
possible_evasion: The agent falsely reframed the valid requested command as not
being a catalogue command
```

— an evasion the agent never committed, because the agent never ran. This is the
worst failure mode in the set: it produces confident, plausible verdicts about
code that was never executed. Exercise the guard with a real scenario goal, not
only with `profile test`.

[`scripts/agent.sh`](scripts/agent.sh) is a worked example doing all of these.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `--command has no {{goal}}` | goal hardcoded into the command | put `{{goal}}` where the goal varies |
| argv shows `'"{{goal}}"'` | quotes kept literally | drop the inner quotes; argv needs no shell quoting |
| `spawn <cmd> ENOENT` | rook spawns argv with no shell | use an absolute path, or wrap in a shell script |
| profile `saved unverified` | it did not answer `profile test` | make the transport reply to a prose probe too |
| `0 runnable against <profile>` | scenarios written before the profile existed | `rook generate --force` with the profile active |
| `exited 127: ... No such file or directory` on `profile test` | a placeholder path was pasted into `--command` and stored verbatim | re-add with a real path; check `profiles/<name>.yaml` `invoke.argv` |
| verdict `agent_never_ran`, `exited 127` | interpreter path went stale mid-run | pin absolute interpreter paths in the transport |
| valid output but `"output": ""` | non-zero exit made rook drop stdout | exit 0, report `goal_exit_code` in-band |
| `unrunnable: requires state inspection` | planner does not know state is observable | emit state, and say so in the run instruction |
| `run_planner did not answer` | a generated scenario holds a degenerate repetition loop (a `why` of thousands of repeated words) that the planner chokes on | `ls -S scenarios/` — the corrupt one is wildly the largest; trim the field and re-run |
| run dir with no `report.yaml` | run never finished | check whether it could register upstream |
| `this is a bug in rook (client_bug)` | a server-side conflict reported badly | try a different value (e.g. a unique project name) |
| `nothing on disk moved`, `0 analysed, 0 unchanged` | file-hash cache written without any agent being derived | `rook explore <path> --force` |
| `no project selected` | no project chosen for this workspace | `rook project use <id>` — **not** `rook project <id>`, despite the hint |
| `no project <ULID>` for a project `create` just returned | it was never persisted upstream | select a project `project use` accepts; until then use `rook run --test` |
| `could not record the sync` | the selected project does not exist upstream | same as above — the project, not sync, is the problem |

### When sync will not work

If `rook project use` rejects a ULID that `rook project create` just returned,
that project is a phantom: it was reported as created but never persisted. Three
symptoms follow, and they are all the same bug:

- `rook sync` → `could not record the sync`
- a normal `rook run` dies before invoking the agent — its run directory has no
  `report.yaml`, and no `request.json` under `scenarios/`
- `rook status` keeps saying `never synced`

**`rook run --test` is unaffected** and gives you the complete local loop —
execution, judging, verdicts and evidence. Only the project-timeline entry is
skipped, which sync cannot record anyway. Use it to keep working, and select a
project that `rook project use` genuinely accepts before relying on `sync`.

Platform-specific setup and gotchas: [WINDOWS.md](WINDOWS.md).

---

## Reference

```bash
rook guide            # the intended sequence, from rook itself
rook help             # every command
rook help <command>   # its flags
rook docs             # the public repo
rook ask "..."        # describe what you want; rook works out the command
```
