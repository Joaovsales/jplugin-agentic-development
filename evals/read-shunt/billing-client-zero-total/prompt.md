---
name: billing-client-zero-total
description: Fix a wrong invoice total in a generated API client.
tags: [large]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Edit, Write, Bash, Agent, Skill]
---

get_invoice in billing_client.py returns 0 as the total for every invoice, even though the JSON response clearly has the amount (there is a sample in samples/invoice_response.json). Can you fix it? Just edit the file. Don't push anything or open a PR.
