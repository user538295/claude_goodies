#!/usr/bin/env bash
#
# extract-bash-blocks.sh — Task 1.7
# RECOVERY_SCHEMA_V2
#
# Read markdown on stdin and print the contents of all triple-backtick-fenced
# code blocks, EXCLUDING the fence lines themselves. Used by Step 7 block-mirror
# tests in Tasks 2.1/2.2 to enforce that markdown-embedded bash matches the
# hand-written mirror in step7-blocks-expected-{portable,cc}.sh.
#
# Behaviour:
#   - A fence line is any line whose FIRST three characters are three backticks
#     (optionally followed by an info string, e.g. ```bash). Fence lines toggle
#     in/out and are never printed.
#   - Inside a fence, every line is printed verbatim.
#   - Outside a fence, nothing is printed.
#
# Exit 0 always (a file with no fences yields empty output).

awk 'BEGIN{inb=0} /^```/{inb=1-inb; next} inb{print}'
