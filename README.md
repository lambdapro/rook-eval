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

```bash
cd example
./agent/catalogue.sh borrow b-1     # the agent
./transport.sh 'catalogue borrow b-1'  # what rook invokes
```

Then follow [`example/README.md`](example/README.md) for the full loop —
`explore` → `profile add` → `generate` → `scenarios list` → `run` → `report`.

The example is built to demonstrate the failure modes that actually bite:
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
rook doctor          # CLI, node, workspace, controller reachability, auth, tty
rook plan            # account, organisation, credit balance
```

### 1. Sign in and pick a project

```bash
rook login           # browser flow; needs a TTY
rook whoami

rook project                  # list selectable projects
rook project use <ULID>       # select an existing one
rook project create <name>    # or make a new one, and select it
```

### 2. Point rook at the codebase

```bash
rook explore .
rook explore <path> -- "free text describing what the agent is"
```

This writes **features** — one per capability it finds. Review them; everything
downstream is derived from them.

```bash
rook agent use <agent-id>     # if it found more than one
```

### 3. Describe how to reach the agent — DO THIS BEFORE `generate`

> **This is the single most important ordering rule.** rook's own guide lists
> `generate` as step 5 and `profile add` as step 6, but generating scenarios
> while no profile exists makes the planner assume a rich agent — multi-turn
> conversation, observable tool calls, file inputs. If your transport is a
> single-shot command, those scenarios can never run, and no amount of editing
> the profile fixes it because the assumptions are baked into the scenarios.

```bash
# From a command line — {{goal}} is where each scenario's goal is substituted
rook profile add <name> --command 'claude -p "{{goal}}"'

# Or from a curl (file, or piped on stdin)
rook profile add <name> --from ./request.curl

rook profile test <name>      # MUST answer, or it stays unverified and unusable
rook profile show <name>
rook profile use <name>
```

`--command` **must** contain `{{goal}}`. rook spawns argv directly with no
shell, so `{{goal}}` stays one token — do not wrap it in quotes, or the quote
characters are passed to your agent literally.

### 4. Write scenarios

```bash
rook generate
rook generate --total 20 --class functional,adversarial
rook generate --force -- "constraints the scenarios must respect"
```

Use the trailing instruction to tell the planner what your transport can
actually do. It is the cheapest lever you have.

### 5. Check runnability — free, and do it every time

```bash
rook scenarios list
```

Reports `N runnable against <profile>` and, for anything unrunnable, exactly
why. **If this says `0 runnable`, stop.** Running would only pay for planning
and produce skips. Fix the profile or regenerate first.

```bash
rook scenarios exclude SC-001 SC-002    # keep on disk, leave out of runs
rook scenarios include SC-001
rook scenarios delete SC-003
```

### 6. Run

```bash
rook run --concurrency 1
rook run --only SC-013,SC-015
rook run --class adversarial --category jailbreak,prompt_injection
rook run --test                          # keep out of the project timeline
rook run --profile <name> -- "what the transport returns"
```

Useful flags: `--tag`, `--name`, `--resume <id>`, `--rca`, `--json`,
`--verbose`, `--allow 'bash(npm test)'`.

Runnability is re-decided **on every run** by a model reading each scenario
against the profile. It cannot know anything your transport does that the
profile does not state — so say it in the trailing instruction.

### 7. Read the results

```bash
rook report                  # newest run
rook report <RUN_ID>
rook report --rca            # explains failure clusters — costs credits
rook ui --local              # browser viewer, works fully offline
rook ui --local --no-open    # print the URL instead
rook status                  # where this machine stands
```

Everything is also on disk:

```
.testmuai/rook/projects/<PROJECT>/agents/<AGENT>/
├── features/     F-001.yaml …           what the agent is meant to do
├── scenarios/    SC-001.yaml …          goal + acceptance criteria
├── profiles/     <name>.yaml            how the agent is invoked
└── runs/<RUN_ID>/
    ├── run.yaml      included/skipped per scenario, with the planner's reason
    ├── report.yaml   totals, credits, quality metrics, failure clusters
    └── scenarios/SC-013/
        ├── request.json   exact goal sent
        ├── response.json  raw output, exit_code, latency, transcript
        └── verdict.yaml   per-criterion Pass/Fail with quoted evidence
```

A run directory with no `report.yaml` never finished.

**Read `verdict.yaml` and `response.json` before reaching for `--rca`.** They
are free and factual; the RCA is a model's interpretation and costs credits.

### 8. Record it upstream

```bash
rook sync                    # every agent, as one write
rook runs sync               # push finished runs that still owe upstream
```

Nothing leaves your machine until you do this.

---

## Writing a transport that works

Scenario `goal` fields are whatever `generate` decided they should be — often a
literal command. The profile's job is to turn a goal into a real invocation and
return text the judge can grade. Three rules earn their keep:

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

[`scripts/agent.sh`](scripts/agent.sh) is a worked example doing all three.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `--command has no {{goal}}` | goal hardcoded into the command | put `{{goal}}` where the goal varies |
| argv shows `'"{{goal}}"'` | quotes kept literally | drop the inner quotes; argv needs no shell quoting |
| `spawn <cmd> ENOENT` | rook spawns argv with no shell | use an absolute path, or wrap in a shell script |
| profile `saved unverified` | it did not answer `profile test` | make the transport reply to a prose probe too |
| `0 runnable against <profile>` | scenarios written before the profile existed | `rook generate --force` with the profile active |
| verdict `agent_never_ran`, `exited 127` | interpreter path went stale mid-run | pin absolute interpreter paths in the transport |
| valid output but `"output": ""` | non-zero exit made rook drop stdout | exit 0, report `goal_exit_code` in-band |
| `unrunnable: requires state inspection` | planner does not know state is observable | emit state, and say so in the run instruction |
| run dir with no `report.yaml` | run never finished | check whether it could register upstream |
| `this is a bug in rook (client_bug)` | a server-side conflict reported badly | try a different value (e.g. a unique project name) |

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
