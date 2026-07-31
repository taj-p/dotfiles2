#!/usr/bin/env sh

# Codex Stop hooks require valid JSON on stdout. llm-watch itself deliberately
# stays silent so the same CLI can serve other lifecycle events.
"$HOME/.local/bin/llm-watch" hook codex
printf '{}\n'
exit 0
