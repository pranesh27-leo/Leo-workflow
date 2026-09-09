# Plan: MIT licence

Created: 2026-09-08

## Goal
Add an MIT licence so the repository can legally be used, forked and vendored.
Copyright holder: Pranesh Kumar.

## Non-goals
- No per-file SPDX headers. 2,253 lines across 20 files, and every one of them
  would carry a comment that says nothing about what the file does.
- No CONTRIBUTING, no CLA, no code of conduct. Not asked for.
- No licence scanning of the six third-party tools. That is C3's question and
  it is about egress, not licensing.

## Wrong-change signal
The licence names anyone other than Pranesh Kumar, or the year is not 2026.

## Tasks

| #  | Task                                     | Files            | Est LOC | Status |
|----|------------------------------------------|------------------|---------|--------|
| T1 | LICENSE at the root, MIT, 2026           | LICENSE          | 21      | done   |
| T2 | README states the licence and links it   | README.md        | 3       | done   |

## Budget
est: 25 LOC
