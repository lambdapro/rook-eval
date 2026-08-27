# Running rook on Windows

Everything here was established by actually hitting it on Windows 11 with Git
Bash. None of it applies to macOS or Linux.

---

## Installing

**The public installer refuses to run on Windows.**

```bash
curl -fsSL https://raw.githubusercontent.com/LambdaTest/rook/main/install.sh | bash
# Error: install.sh does not support Windows shells (uname -s reported 'MINGW64_NT-...')
```

`detect_platform()` rejects MINGW/MSYS/CYGWIN because the tarball's bundled
`bin/rook` launcher is a POSIX shell script. The installer suggests WSL.

Three options if you have no WSL:

**1. The win-x64 release tarball.** Every release *does* publish
`rook-<version>-win-x64.tar.gz` with a bundled `node.exe`, and the CLI entry
point `rook.cjs` is genuinely win32-aware (it resolves
`@testmuai/rook-node-win-x64/bin/node.exe` and has explicit Windows signal
handling). Only the launcher is POSIX-only. Extract it and write your own
`.cmd`:

```bat
@echo off
setlocal
set "ROOK_ROOT=%USERPROFILE%\.testmuai\rook-<version>"
set "ROOK_ENTRY=%ROOK_ROOT%\lib\node_modules\@lambdatestincprivate\rook\bin\rook.cjs"
set "ROOK_NODE=%ROOK_ROOT%\lib\node_modules\@testmuai\rook-node-win-x64\bin\node.exe"
if exist "%ROOK_NODE%" ( "%ROOK_NODE%" "%ROOK_ENTRY%" %* ) else ( node "%ROOK_ENTRY%" %* )
exit /b %ERRORLEVEL%
```

Verify the published `.sha256` sidecar before extracting.

**2. npm.** `@testmuai/rook` exists on the public registry; npm generates the
`.cmd` shim for you. Needs Node 20+ on PATH.

**3. An internal build**, if you have one. `VERSION` will be a git SHA rather
than a semver, and it may point at a different environment (stage rather than
prod) with a **separate project namespace** — a project created on one is
invisible to the other.

### Do not end up with two installs

Check `where rook` / `command -v rook` before installing anything. Two copies on
PATH pointing at different environments is a confusing failure mode: your
project appears to vanish depending on which one runs.

---

## PATH and shell setup

### Git Bash never sources `~/.bashrc`

Git Bash starts a **login** shell, which reads `~/.profile`. Its `/etc/profile`
does **not** source `~/.bashrc`, and `/etc/bash.bashrc` doesn't either. If you
have no `~/.bash_profile`, everything in `~/.bashrc` — version managers,
exported variables — silently never loads in a normal Git Bash window.

Put PATH changes in `~/.profile`, and source `.bashrc` from it explicitly if you
want it:

```sh
case ":$PATH:" in
  *":/d/rook/bin:"*) ;;
  *) [ -d /d/rook/bin ] && export PATH="/d/rook/bin:$PATH" ;;
esac

# LAST — Git Bash login shells do not do this on their own.
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
```

### Use POSIX paths in bash

```sh
export PATH="/d/rook/bin:$PATH"     # correct
export PATH="D:\rook\bin:$PATH"     # breaks PATH
```

`:` is bash's PATH separator, so `D:\rook\bin` splits into two junk entries
(`D` and `\rook\bin`), and the backslashes read as escapes.

### A new terminal is not always enough

Setting the user PATH only affects newly launched processes. An already-open
window keeps its old environment — and a **VS Code / Cursor integrated terminal
inherits the environment the editor was launched with**, so a new terminal tab
won't help. Restart the editor.

---

## Spawning: the three failures that bite

rook spawns a profile's argv **directly, with no shell**. On Windows that breaks
three ways.

**1. npm shims are not executable.** A global npm install creates `tool`,
`tool.cmd` and `tool.ps1`. The extensionless `tool` is a `/bin/sh` script
Windows cannot exec, so `--command 'tool …'` fails:

```
spawn tool ENOENT
```

**2. `.cmd` cannot be spawned either.** Pointing at `tool.cmd` does not help —
Node 24 refuses to spawn `.bat`/`.cmd` without `shell: true` (the
CVE-2024-27980 fix).

**3. `bash` may not be on PATH.** Git for Windows puts `git.exe` in
`D:\Git\cmd` but `bash.exe` in `D:\Git\bin`, and typically only the former is on
PATH. Use the absolute path.

The fix for all three is to call the real interpreter with the real script:

```bash
rook profile add <name> --command 'D:\Git\bin\bash.exe /path/to/agent.sh {{goal}}'
# or
rook profile add <name> --command 'node C:\path\to\node_modules\pkg\bin\cli.cjs run {{goal}}'
```

---

## Version managers will break a run

This one is subtle and cost a full debugging session.

`fnm` creates a symlink per shell session under
`%LOCALAPPDATA%\fnm_multishells`, named `<pid>_<epoch_ms>`, and puts it on
PATH. It is meant to be removed when the shell exits; under Git Bash on Windows
that cleanup often does not run, so they accumulate — tens of thousands of them.

When rook spawns a process, that process inherits a PATH entry pointing at one
of those directories. If its owning shell is gone, `node` is not there, and the
command dies with **exit 127 after already having produced output**. rook then
discards the output (non-zero exit) and records the verdict as
`agent_never_ran` — a failure that looks nothing like its cause.

**Pin an absolute interpreter path inside your transport:**

```bash
export PATH="/c/nvm4w/nodejs:$PATH"   # a real install, not a per-shell shim
```

Check for accumulation with:

```powershell
(Get-ChildItem "$env:LOCALAPPDATA\fnm_multishells").Count
```

Delete only links older than a few days — recent ones may belong to live shells,
and removing those breaks `node` in them immediately. Delete the **link**
(`.Delete()`), never `Remove-Item -Recurse`, which can follow a directory
symlink and destroy the shared target every other link points at.

---

## Checklist

```bash
rook doctor                       # controller reachable, auth, workspace
command -v rook kane-cli node     # all resolve?
node --version                    # is it a per-shell shim path?
rook profile test <name>          # must answer
rook scenarios list               # runnable > 0 before spending anything
```
