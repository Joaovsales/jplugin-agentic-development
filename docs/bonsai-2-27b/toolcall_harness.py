#!/usr/bin/env python3
"""Fixed 5-prompt tool-calling round-trip harness for an OpenAI-compatible llama-server.

Each case sends a user prompt with a tool list, checks the model's tool call(s)
(name + arguments), executes a canned fake tool, returns the result, and checks
the final assistant answer. Stdlib only. Loopback only.

Usage: python3 -I toolcall_harness.py [--base http://127.0.0.1:18080] \
           [--effort none|medium|xhigh] [--max-tokens 8192] [--out results.json]
"""
import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request

MAX_TURNS = 4


def tool(name, desc, props, required):
    return {"type": "function", "function": {
        "name": name, "description": desc,
        "parameters": {"type": "object", "properties": props, "required": required}}}


TOOLS = {
    "get_weather": tool("get_weather", "Get current weather for a city.",
                        {"city": {"type": "string"}}, ["city"]),
    "convert_currency": tool("convert_currency", "Convert an amount between ISO-4217 currencies.",
                             {"amount": {"type": "number"}, "from_currency": {"type": "string"},
                              "to_currency": {"type": "string"}},
                             ["amount", "from_currency", "to_currency"]),
    "search_files": tool("search_files", "Search the workspace for files by name; returns paths.",
                         {"name": {"type": "string"}}, ["name"]),
    "get_file_info": tool("get_file_info", "Return size in bytes and owner of a file path.",
                          {"path": {"type": "string"}}, ["path"]),
    "create_event": tool("create_event", "Create a calendar event.",
                         {"title": {"type": "string"},
                          "date": {"type": "string", "description": "YYYY-MM-DD"},
                          "duration_minutes": {"type": "integer"},
                          "attendees": {"type": "array", "items": {"type": "string"}}},
                         ["title", "date", "duration_minutes", "attendees"]),
}

WEATHER = {"lisbon": {"temp_c": 21, "condition": "sunny"},
           "paris": {"temp_c": 9, "condition": "rain"},
           "tokyo": {"temp_c": 14, "condition": "cloudy"}}


def fake_exec(name, args):
    if name == "get_weather":
        return WEATHER.get(str(args.get("city", "")).split(",")[0].strip().lower(), {"error": "unknown city"})
    if name == "convert_currency":
        return {"converted": 231.47, "currency": "EUR"}
    if name == "search_files":
        return {"paths": ["/srv/finance/budget-2026.xlsx"]}
    if name == "get_file_info":
        ok = args.get("path") == "/srv/finance/budget-2026.xlsx"
        return {"size_bytes": 48213, "owner": "marta"} if ok else {"error": "no such file"}
    if name == "create_event":
        return {"event_id": "evt_7731", "status": "created"}
    return {"error": "unknown tool"}


def check_weather_city(*cities):
    want = {c.lower() for c in cities}
    def chk(calls):
        got = {str(a.get("city", "")).split(",")[0].strip().lower() for n, a in calls if n == "get_weather"}
        return want <= got, f"cities called={sorted(got)} want={sorted(want)}"
    return chk


def chk_currency(calls):
    for n, a in calls:
        if n == "convert_currency":
            ok = (float(a.get("amount", -1)) == 250.0 and str(a.get("from_currency", "")).upper() == "USD"
                  and str(a.get("to_currency", "")).upper() == "EUR")
            return ok, f"args={a}"
    return False, "convert_currency not called"


def chk_event(calls):
    for n, a in calls:
        if n == "create_event":
            att = a.get("attendees")
            ok = (a.get("date") == "2026-11-20" and a.get("duration_minutes") == 30
                  and isinstance(att, list) and {x.lower() for x in att} >= {"ana@example.com", "rui@example.com"})
            return ok, f"args={a}"
    return False, "create_event not called"


def chk_chain(calls):
    names = [n for n, _ in calls]
    ok = names[:1] == ["search_files"] and any(
        n == "get_file_info" and a.get("path") == "/srv/finance/budget-2026.xlsx" for n, a in calls)
    return ok, f"sequence={names}"


CASES = [
    {"id": "1-single", "tools": ["get_weather"],
     "prompt": "What's the weather in Lisbon right now? Use the tool.",
     "check_calls": check_weather_city("Lisbon"), "answer_has": ["21"]},
    {"id": "2-select", "tools": ["get_weather", "convert_currency", "search_files"],
     "prompt": "Convert 250 USD to EUR for me.",
     "check_calls": chk_currency, "answer_has": ["231.47"]},
    {"id": "3-parallel", "tools": ["get_weather"],
     "prompt": "Compare the current weather in Paris and in Tokyo.",
     "check_calls": check_weather_city("Paris", "Tokyo"), "answer_has": ["9", "14"]},
    {"id": "4-typed-args", "tools": ["create_event", "get_weather"],
     "prompt": ("Book a 30-minute meeting titled 'Q4 budget review' on 2026-11-20 with "
                "ana@example.com and rui@example.com."),
     "check_calls": chk_event, "answer_has": ["evt_7731"]},
    {"id": "5-chained", "tools": ["search_files", "get_file_info"],
     "prompt": "Find the budget spreadsheet in the workspace and tell me its size in bytes and its owner.",
     "check_calls": chk_chain, "answer_has": ["48213", "marta"]},
]


def post(base, body, timeout):
    req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def run_case(case, base, effort, max_tokens, timeout):
    msgs = [{"role": "system", "content": "You are a helpful assistant. Use the provided tools when they help."},
            {"role": "user", "content": case["prompt"]}]
    tools = [TOOLS[t] for t in case["tools"]]
    calls, notes, usage, t0 = [], [], {"completion_tokens": 0}, time.time()
    final = None
    for _ in range(MAX_TURNS):
        body = {"messages": msgs, "tools": tools, "max_tokens": max_tokens, "reasoning_effort": effort}
        resp = post(base, body, timeout)
        usage["completion_tokens"] += resp.get("usage", {}).get("completion_tokens", 0)
        msg = resp["choices"][0]["message"]
        tcs = msg.get("tool_calls") or []
        if not tcs:
            final = msg.get("content") or ""
            notes.append(f"finish_reason={resp['choices'][0].get('finish_reason')}")
            break
        # Do not echo reasoning back (KNOWN_ISSUES: tool-loop cache misses).
        msgs.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": tcs})
        for tc in tcs:
            fn = tc["function"]["name"]
            try:
                args = json.loads(tc["function"].get("arguments") or "{}")
            except json.JSONDecodeError as e:
                return {"pass": False, "reason": f"malformed arguments JSON: {e}: {tc['function'].get('arguments')!r}"}
            if not isinstance(args, dict):
                return {"pass": False, "reason": f"arguments is not a JSON object: {args!r}"}
            calls.append((fn, args))
            msgs.append({"role": "tool", "tool_call_id": tc.get("id", ""), "content": json.dumps(fake_exec(fn, args))})
    # Argument values are model output: a wrong type ("250 USD" for a number) is a FAIL, not a crash.
    try:
        calls_ok, calls_note = case["check_calls"](calls)
    except (TypeError, ValueError) as e:
        calls_ok, calls_note = False, f"argument of wrong type: {e}"
    # Digit-group separators are formatting, not content: "48,213" counts as "48213".
    norm = re.sub(r"(?<=\d)[,  ](?=\d{3})", "", final or "").lower()
    ans_ok = final is not None and all(s.lower() in norm for s in case["answer_has"])
    return {"pass": calls_ok and ans_ok, "calls_ok": calls_ok, "answer_ok": ans_ok, "calls": calls,
            "calls_note": calls_note, "final": (final or "")[:600], "notes": notes,
            "completion_tokens": usage["completion_tokens"], "seconds": round(time.time() - t0, 1)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:18080")
    ap.add_argument("--effort", default="none")
    ap.add_argument("--max-tokens", type=int, default=8192)
    ap.add_argument("--timeout", type=int, default=3600)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    if not a.base.startswith(("http://127.0.0.1", "http://localhost")):
        sys.exit("refusing non-loopback base URL")
    results = {}
    for case in CASES:
        try:
            r = run_case(case, a.base, a.effort, a.max_tokens, a.timeout)
        except (urllib.error.URLError, KeyError, TimeoutError) as e:
            detail = e.read().decode()[:400] if isinstance(e, urllib.error.HTTPError) else ""
            r = {"pass": False, "reason": f"{type(e).__name__}: {e} {detail}"}
        results[case["id"]] = r
        print(f"{case['id']}: {'PASS' if r['pass'] else 'FAIL'} {json.dumps({k: v for k, v in r.items() if k != 'pass'})}",
              flush=True)
    print(f"TOTAL {sum(r['pass'] for r in results.values())}/{len(CASES)} (effort={a.effort})")
    if a.out:
        with open(a.out, "w") as f:
            json.dump({"effort": a.effort, "results": results}, f, indent=2, default=str)


if __name__ == "__main__":
    main()
