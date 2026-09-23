#!/usr/bin/env pwsh
<#
.SYNOPSIS
  leo — keep AI-written code reviewable. PowerShell entry point.

.DESCRIPTION
  This is a wrapper, not a port. leo is one bash implementation and stays one:
  a second implementation in PowerShell would be two programs that have to
  agree about every check, every message and every exit code, and the day they
  stop agreeing is the day leo starts passing a check on one platform that it
  fails on the other. There is no version of that which is worth having in a
  tool whose entire job is to be trusted about whether a change was reviewed.

  So this finds a bash, checks it can actually run leo, and hands over. What
  it adds is the part a `.cmd` shim cannot: a preflight that says exactly what
  is missing, instead of letting the user meet it as a wall of
  "command not found".

  It looks for bash in this order, and the order is deliberate:

    1. $env:LEO_BASH            an explicit override always wins
    2. bash on PATH             Git Bash, MSYS2, Cygwin, or a real Unix
    3. Git for Windows          the usual install, found via git itself
    4. well-known locations     Program Files, the per-user install
    5. WSL                      last, and only as a fallback -- see below

  WSL is last because it is a different filesystem with a different view of
  the repository. `wsl bash` sees C:\work as /mnt/c/work, git inside WSL may be
  a different git with different config, and line endings and file modes cross
  the boundary in ways that produce a leo that works and a repository that is
  subtly wrong. It is offered because it beats not running at all, and it is
  offered last because Git Bash is the right answer.

.EXAMPLE
  leo init
.EXAMPLE
  leo plan "rate limiting"
.EXAMPLE
  $env:LEO_BASH = 'C:\msys64\usr\bin\bash.exe'; leo check
.LINK
  https://github.com/pranesh27-leo/Leo-workflow
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The script's own directory, resolving a symlink if this was linked onto the
# PATH. $PSCommandPath is the file being run; $PSScriptRoot is its directory.
# Both exist in PowerShell 3.0 and later, which is every Windows since 8.
$LeoHome = $PSScriptRoot
$LeoScript = Join-Path $LeoHome 'leo'

function Write-LeoError {
    param([string]$Message, [string[]]$Detail = @())
    # stderr, not the error stream: leo's own messages go to stderr and a
    # caller redirecting 2> should get all of them together.
    [Console]::Error.WriteLine("ERR  $Message")
    foreach ($line in $Detail) { [Console]::Error.WriteLine("     $line") }
}

if (-not (Test-Path -LiteralPath $LeoScript)) {
    Write-LeoError "leo is not next to this wrapper" @(
        "expected: $LeoScript",
        "This file must stay in the directory it was installed in.",
        "Reinstall with: npm install -g leo-workflow"
    )
    exit 1
}

# --- find a bash ----------------------------------------------------------
# Every candidate is checked for existence AND for being able to run, because
# a path that exists and cannot execute is the more confusing failure of the
# two: PATH lookups on Windows routinely find a stub, an App Execution Alias,
# or a 0-byte placeholder from an uninstalled package.
function Test-BashCandidate {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $probe = & $Path -c 'printf ready' 2>$null
        return ($LASTEXITCODE -eq 0 -and $probe -eq 'ready')
    } catch {
        return $false
    }
}

function Find-Bash {
    # 1. An explicit override. Checked first and reported loudly if it is
    #    wrong: someone who sets LEO_BASH and gets silently ignored will spend
    #    a long time wondering which bash ran.
    if ($env:LEO_BASH) {
        if (Test-BashCandidate $env:LEO_BASH) { return $env:LEO_BASH }
        Write-LeoError "LEO_BASH is set but cannot run: $($env:LEO_BASH)" @(
            "Unset it, or point it at a working bash.exe."
        )
        exit 1
    }

    # 2. PATH. Get-Command returns every match; Where-Object drops the WSL
    #    shim (a bash.exe in System32 that launches a distribution) so it is
    #    considered under WSL below rather than mistaken for a native bash.
    $onPath = @(Get-Command bash -All -ErrorAction SilentlyContinue |
                Where-Object { $_.Source -and $_.Source -notmatch '\\System32\\bash\.exe$' } |
                ForEach-Object { $_.Source })
    foreach ($candidate in $onPath) {
        if (Test-BashCandidate $candidate) { return $candidate }
    }

    # 3. Git for Windows, located through git itself rather than guessed.
    #    git.exe lives in <install>\cmd or <install>\mingw64\bin; bash is in
    #    <install>\bin.
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and $git.Source) {
        $dir = Split-Path -Parent $git.Source
        foreach ($up in @('..', '..\..')) {
            $guess = Join-Path (Join-Path $dir $up) 'bin\bash.exe'
            try { $guess = (Resolve-Path -LiteralPath $guess -ErrorAction Stop).Path } catch { continue }
            if (Test-BashCandidate $guess) { return $guess }
        }
    }

    # 4. The usual install locations, including the per-user one that does not
    #    need an administrator and is therefore common on locked-down machines.
    $wellKnown = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:SystemDrive\msys64\usr\bin\bash.exe",
        "$env:SystemDrive\cygwin64\bin\bash.exe"
    )
    foreach ($candidate in $wellKnown) {
        if (Test-BashCandidate $candidate) { return $candidate }
    }

    return $null
}

$bash = Find-Bash

if (-not $bash) {
    # WSL last. Named explicitly rather than used silently: running leo across
    # the WSL boundary is a real choice with real consequences, and the user
    # should make it rather than discover it.
    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    Write-LeoError "no bash found — leo is a bash program and needs one" @(
        "",
        "The supported answer is Git for Windows, which ships the bash leo wants:",
        "    winget install --id Git.Git -e",
        "    https://git-scm.com/download/win",
        "",
        "Already have one somewhere else? Point leo at it:",
        "    `$env:LEO_BASH = 'C:\path\to\bash.exe'",
        $(if ($wsl) {
            "Or run leo inside WSL, where it is a native Unix tool:`n     wsl leo $($Arguments -join ' ')"
        } else {
            "WSL is not installed, so that route is not available here."
        })
    )
    exit 1
}

# --- preflight ------------------------------------------------------------
# leo uses a small, fixed set of POSIX tools. Git for Windows ships all of
# them; a stripped MSYS2 or a Cygwin without coreutils may not. Checking once,
# here, turns "awk: command not found" buried in the middle of a check into
# one line naming the tool and the install that provides it.
#
# Skipped when LEO_SKIP_PREFLIGHT is set, because it costs a process spawn on
# every invocation and somebody running leo in a loop should be able to say
# they already know.
if (-not $env:LEO_SKIP_PREFLIGHT) {
    $required = 'git awk sed grep tr cut sort wc head tail basename dirname find mktemp readlink date cksum'
    $missing = & $bash -c "for t in $required; do command -v `$t >/dev/null 2>&1 || printf '%s ' `$t; done" 2>$null
    if ($missing) {
        Write-LeoError "that bash cannot run leo — missing: $($missing.Trim())" @(
            "bash: $bash",
            "",
            "leo needs a POSIX toolchain, not just a shell. Git for Windows",
            "ships all of it; a minimal MSYS2 or Cygwin may not.",
            "",
            "Set `$env:LEO_SKIP_PREFLIGHT = '1' to bypass this check."
        )
        exit 1
    }
}

# --- hand over ------------------------------------------------------------
# The arguments go through as an array, never as a joined string. Joining them
# would mean re-quoting, and leo takes free text: `leo plan "rate limiting"`
# and `leo defer T3 "waiting on the vendor's key"` both contain characters
# that a hand-rolled quoting pass gets wrong. PowerShell's native argument
# passing already does this correctly.
#
# The script path is passed as-is. Git Bash accepts a Windows path here and
# converts it internally; converting it to /c/... by hand is how a path with a
# space in it gets split.
$exitCode = 0
try {
    if ($Arguments) {
        & $bash $LeoScript @Arguments
    } else {
        & $bash $LeoScript
    }
    $exitCode = $LASTEXITCODE
} catch {
    Write-LeoError "failed to run leo through $bash" @($_.Exception.Message)
    exit 1
}

# leo's exit codes are part of its contract: 0 success, 1 a check failed,
# 2 leo commit refused because no human was present. Swallowing them would
# make every `if (leo check)` in a script wrong.
exit $exitCode
