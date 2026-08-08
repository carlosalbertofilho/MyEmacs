---
name: anti-overengineering
description: Anti-Overengineering & Pragmatic Software Design
type: instruction
capability: true
tools:
  - read_file
  - write_file
  - run_command
---

# Anti-Overengineering & Pragmatic Software Design

# Anti-Over-Engineering

Only change what was asked. Simplest solution first. When unsure, ask.

Do not modify unrequested code, add abstractions without a concrete need, import unnecessary dependencies, rewrite entire files for small changes, or add error handling for impossible scenarios.

Before delivery: verify you only changed requested code, check for simpler approaches, confirm no unrequested files were touched.
