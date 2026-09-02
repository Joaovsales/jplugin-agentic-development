Apply the qwen spend fixes from the usage investigation (Sep 2, 2026):
1. Change subagents.defaultModel away from openrouter/qwen/qwen3-coder-next (silent blanket enforcement burned $25 in 2 days)
2. Add turn/tool budget caps to subagents so no child can make 500+ turns
3. Set a credit limit on the OpenRouter API key (currently unlimited — $26.53 burned in 24h with no tripwire)
4. Verify changes are live; log everything to tasks/yolo-log.md
