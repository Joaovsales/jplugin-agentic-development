"""One-run, localhost-only admission guard. See admission-gateway.md for assumptions."""
import argparse
from decimal import Decimal as D
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import secrets
import threading
import urllib.error
import urllib.request

MODEL = "claude-opus-5-5"
SERVED = {MODEL, "claude-opus-4-8"}
MILLION = D(1000000)
STRUCTURAL_ALLOWANCE = 65536
GEO = D("1.1")
TOP = {"model", "max_tokens", "messages", "system", "tools", "tool_choice",
       "stream", "temperature", "top_p", "top_k", "stop_sequences", "thinking",
       "metadata", "service_tier", "speed", "output_config", "context_management", "diagnostics"}
BETAS = {"claude-code-20250219", "interleaved-thinking-2025-05-14",
         "context-management-2025-06-27", "per-turn-control-2026-07-01",
         "mid-conversation-tool-changes-2026-07-01", "thinking-token-count-2026-05-13",
         "advanced-tool-use-2025-11-20", "effort-2025-11-24",
         "thinking-display-updates-2026-08-18", "oauth-2025-04-20",
         "prompt-caching-scope-2026-01-05", "tool-provenance-2026-10-26",
         "thinking-binding-controls-2026-08-01", "extended-cache-ttl-2025-04-11",
         "cache-diagnosis-2026-04-07"}
USAGE = {"input_tokens", "output_tokens", "cache_creation_input_tokens",
         "cache_read_input_tokens", "cache_creation", "server_tool_use",
         "service_tier", "speed", "inference_geo", "iterations", "output_tokens_details", "fallback_credit"}


class Denied(ValueError):
    pass


def integer(value):
    return type(value) is int and value >= 0


def structural_nodes(value, depth=0):
    if depth > 32:
        raise Denied("request nesting exceeds the admitted shape")
    if isinstance(value, dict):
        return 1 + sum(structural_nodes(x, depth + 1) for x in value.values())
    if isinstance(value, list):
        return 1 + sum(structural_nodes(x, depth + 1) for x in value)
    return 0


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Denied("duplicate request field")
        result[key] = value
    return result


def blocks(value, system=False):
    if isinstance(value, str):
        return
    if not isinstance(value, list) or len(value) > 512:
        raise Denied("only text content is admitted")
    shapes = {"text": {"type", "text", "cache_control", "citations"},
              "tool_use": {"type", "id", "name", "input", "cache_control"},
              "tool_result": {"type", "tool_use_id", "content", "is_error", "cache_control"},
              "thinking": {"type", "thinking", "signature"},
              "redacted_thinking": {"type", "data"}}
    for block in value:
        if not isinstance(block, dict) or block.get("type") not in shapes:
            raise Denied("unsupported content block")
        if set(block) - shapes[block["type"]] or system and block["type"] != "text":
            raise Denied("unsupported content fields")
        if "cache_control" in block:
            cache_mode(block["cache_control"])
        if block["type"] == "tool_result":
            blocks(block.get("content", ""), system=True)


def cache_mode(control):
    if (not isinstance(control, dict) or set(control) - {"type", "ttl", "scope"}
            or control.get("type") != "ephemeral"
            or control.get("ttl", "5m") not in {"5m", "1h"}
            or control.get("scope", "global") != "global"):
        raise Denied("unsupported cache mode")


def effort_config(config):
    if (not isinstance(config, dict) or set(config) - {"effort"}
            or config.get("effort") not in {"low", "medium", "high", "max"}):
        raise Denied("unsupported output configuration")


def admission(raw):
    body = json.loads(raw.decode("utf-8"), object_pairs_hook=no_duplicates,
                      parse_constant=lambda _: (_ for _ in ()).throw(Denied("nonfinite number")))
    if not isinstance(body, dict) or set(body) - TOP or body.get("model") != MODEL:
        raise Denied("unsupported model or request fields")
    maximum = body.get("max_tokens")
    if not integer(maximum) or not 1 <= maximum <= 4096:
        raise Denied("max_tokens must be between 1 and 4096")
    if body.get("service_tier", "standard_only") != "standard_only" or body.get("speed", "standard") != "standard":
        raise Denied("only standard pricing is admitted")
    if "output_config" in body:
        effort_config(body["output_config"])
    if "context_management" in body and body["context_management"] != {
            "edits": [{"type": "clear_thinking_20251015", "keep": "all"}]}:
        raise Denied("unsupported context management")
    if "diagnostics" in body:
        diagnostic = body["diagnostics"]
        if (not isinstance(diagnostic, dict) or set(diagnostic) != {"previous_message_id"}
                or diagnostic["previous_message_id"] is not None and (
                    not isinstance(diagnostic["previous_message_id"], str)
                    or not re.fullmatch(r"[A-Za-z0-9_-]{1,256}", diagnostic["previous_message_id"]))):
            raise Denied("unsupported diagnostics")
    metadata = body.get("metadata", {})
    if (not isinstance(metadata, dict) or set(metadata) - {"user_id"}
            or not isinstance(metadata.get("user_id", ""), str)):
        raise Denied("unsupported metadata")
    messages = body.get("messages")
    if not isinstance(messages, list) or not 1 <= len(messages) <= 256:
        raise Denied("messages are required")
    for message in messages:
        if isinstance(message, dict) and message.get("role") == "system":
            if (not {"role", "content"} <= set(message) or set(message) - {"role", "content", "output_config"}
                    or not isinstance(message["content"], (str, list))):
                raise Denied("unsupported per-turn control message")
            if "output_config" in message:
                effort_config(message["output_config"])
            blocks(message["content"], system=True)
            continue
        if (not isinstance(message, dict) or set(message) - {"role", "content"}
                or message.get("role") not in {"user", "assistant"}):
            raise Denied("unsupported message shape")
        blocks(message.get("content"))
    blocks(body.get("system", ""), system=True)
    tools = body.get("tools", [])
    if not isinstance(tools, list) or len(tools) > 128:
        raise Denied("unsupported tool array")
    for tool in tools:
        if (not isinstance(tool, dict) or tool.get("type", "custom") != "custom"
                or set(tool) - {"name", "description", "input_schema", "type", "cache_control", "defer_loading", "strict"}):
            raise Denied("server tools are not admitted")
        if "cache_control" in tool:
            cache_mode(tool["cache_control"])
    if "thinking" in body:
        thinking = body["thinking"]
        if (not isinstance(thinking, dict) or set(thinking) - {"type", "budget_tokens", "display"}
                or thinking.get("type") not in {"adaptive", "enabled", "disabled"}
                or thinking.get("display", "updates") not in {"updates", "omitted"}
                or "budget_tokens" in thinking and (not integer(thinking["budget_tokens"])
                                                     or thinking["budget_tokens"] > maximum)):
            raise Denied("unsupported thinking mode")
    bound = len(raw) + STRUCTURAL_ALLOWANCE + 256 * structural_nodes(body)
    amount = GEO * (D(bound) * D(10) + D(maximum) * D(25)) / MILLION
    return secrets.token_hex(12), bound, maximum, amount


def delta_usage(update):
    normalized = dict(update)
    inputs = {"input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"}
    nullable = {"service_tier", "speed", "inference_geo", "iterations", "server_tool_use"}
    for key, value in update.items():
        if (key in inputs and (value is None or type(value) is int and value == 0)
                or key in nullable and value is None):
            normalized.pop(key)
    if "cache_creation" in update:
        cache = update["cache_creation"]
        if cache is None:
            normalized.pop("cache_creation")
        else:
            if (not isinstance(cache, dict) or set(cache) - {"ephemeral_5m_input_tokens", "ephemeral_1h_input_tokens"}
                    or any(n is not None and not integer(n) for n in cache.values())):
                raise Denied("invalid cache delta")
            positive = {k: n for k, n in cache.items() if n is not None and n > 0}
            if not positive:
                normalized.pop("cache_creation")
            else:
                normalized["cache_creation"] = positive
                if "cache_creation_input_tokens" not in normalized:
                    normalized["cache_creation_input_tokens"] = sum(positive.values())
    return normalized


def merge_usage(previous, update, delta=False):
    if not isinstance(update, dict) or set(update) - USAGE:
        raise Denied("unknown usage fields")
    if delta:
        update = delta_usage(update)
    server = update.get("server_tool_use", {})
    if (update.get("service_tier", "standard") != "standard"
            or update.get("iterations", []) != [] or update.get("speed", "standard") != "standard"
            or update.get("inference_geo", "global") not in {"us", "global"}
            or not isinstance(server, dict) or set(server) - {"web_search_requests", "web_fetch_requests"}
            or not all(integer(n) and n == 0 for n in server.values())):
        raise Denied("unknown usage pricing")
    merged = dict(previous)
    counters = {"input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"}
    for key, value in update.items():
        if key in counters and (not integer(value) or value < previous.get(key, 0)):
            raise Denied("decreasing or invalid usage counter")
        if key == "fallback_credit":
            if value is not None:
                raise Denied("unsupported usage credit")
            continue
        if key == "output_tokens_details":
            if value is None:
                continue
            if not isinstance(value, dict) or set(value) - {"thinking_tokens"}:
                raise Denied("unknown output token detail")
            thinking = value.get("thinking_tokens")
            if thinking is None:
                continue
            if not integer(thinking):
                raise Denied("invalid thinking token detail")
            value = {"thinking_tokens": thinking}
        if key == "cache_creation":
            if not isinstance(value, dict) or set(value) - {"ephemeral_5m_input_tokens", "ephemeral_1h_input_tokens"}:
                raise Denied("unknown cache usage")
            old = previous.get(key, {})
            if any(not integer(n) or n < old.get(k, 0) for k, n in value.items()):
                raise Denied("decreasing cache usage")
            value = {**old, **value}
        merged[key] = value
    return merged


def usage_shape(event):
    kinds = {"message_start", "message_delta", "message_stop", "ping", "error",
             "content_block_start", "content_block_delta", "content_block_stop"}
    kind = event.get("type") if isinstance(event, dict) else None
    result = {"event_type": kind if isinstance(kind, str) and kind in kinds else "unknown"}
    message = event.get("message", {}) if isinstance(event, dict) else {}
    update = message.get("usage") if kind == "message_start" and isinstance(message, dict) else (
        event.get("usage") if isinstance(event, dict) else None)
    result["usage_type"] = type(update).__name__
    if isinstance(update, dict):
        result["known_keys"] = sorted(set(update) & USAGE)
        result["unknown_key_count"] = len(set(update) - USAGE)
        result["field_types"] = {k: type(update[k]).__name__ for k in result["known_keys"]}
    return result


def usage_fault(error, event):
    reason = str(error)[:160] if isinstance(error, Denied) else type(error).__name__
    fault = Denied(reason)
    fault.usage_shape = usage_shape(event)
    return fault


def stream_response(wire):
    terminated = wire.endswith((b"\n\n", b"\r\n\r\n"))
    response, phase, delta_seen, thinking_peak = {}, "new", False, 0
    for line in wire.splitlines():
        if not line.startswith((b"data:", b"event:")):
            continue
        event = None
        try:
            if line.startswith(b"data:"):
                event = json.loads(line[5:])
            if phase == "stopped":
                raise Denied("event after message_stop")
            if event is None:
                continue
            kind = event.get("type")
            if kind == "message_start" and phase == "new":
                response, phase = event.get("message", {}), "open"
                response["usage"] = merge_usage({}, response.get("usage", {}))
            elif kind == "message_delta" and phase == "open":
                update = event.get("usage", {})
                if not isinstance(update, dict):
                    raise Denied("invalid message_delta usage")
                if "output_tokens" in update:
                    if not integer(update["output_tokens"]):
                        raise Denied("invalid cumulative output count")
                    delta_seen = True
                response["usage"] = merge_usage(response["usage"], update, delta=True)
            elif kind == "message_stop" and phase == "open" and delta_seen:
                if set(event) - {"type"}:
                    raise Denied("unexpected message_stop fields")
                if thinking_peak > response["usage"].get("output_tokens", 0):
                    raise Denied("thinking detail exceeds cumulative output")
                phase = "stopped"
            elif kind == "ping":
                continue
            elif kind == "error":
                return {}, False
            elif kind == "content_block_start" and phase == "open":
                block = event.get("content_block")
                if not isinstance(block, dict) or block.get("type") not in {"text", "thinking", "redacted_thinking", "tool_use"}:
                    raise Denied("unsupported output content block")
            elif phase == "open" and kind in {"content_block_delta", "content_block_stop"}:
                continue
            else:
                raise Denied("inconsistent message event ordering")
            thinking_peak = max(thinking_peak, response.get("usage", {}).get("output_tokens_details", {}).get("thinking_tokens", 0))
        except (ValueError, TypeError, AttributeError) as error:
            raise usage_fault(error, event) from None
    return response, phase == "stopped" and terminated


class Budget:
    def __init__(self, audit=None):
        if audit:
            try:
                Path(audit).touch(exist_ok=False)
            except FileExistsError as error:
                raise Denied("audit path must be new; prior reservations cannot be reset") from error
        self.lock = threading.RLock()
        self.spent, self.held, self.events = D(0), {}, []
        self.audit, self.blocked = audit, False

    def record(self, event, **fields):
        with self.lock:
            row = {"event": event, **fields, "spent": str(self.spent),
                   "held": str(sum(self.held.values(), D(0)))}
            self.events.append(row)
            if self.audit:
                with Path(self.audit).open("a") as stream:
                    stream.write(json.dumps(row) + "\n")

    def reserve(self, token, amount, info):
        with self.lock:
            if not amount.is_finite() or amount < 0 or token in self.held:
                raise Denied("invalid reservation")
            if self.blocked or amount + self.spent + sum(self.held.values(), D(0)) > D(4):
                self.record("denied", id=token, reservation=str(amount), **info)
                raise Denied("run budget has insufficient unreserved headroom")
            self.held[token] = amount
            self.record("reserved", id=token, reservation=str(amount), **info)

    def settle(self, token, amount):
        with self.lock:
            if amount > self.held[token]:
                self.blocked = True
                self.record("bound_breach", id=token, accounted_upper=str(amount))
                return
            del self.held[token]
            self.spent += amount
            self.record("settled", id=token, accounted_upper=str(amount))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


class Gateway(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, audit=None, opener=None):
        self.capability = secrets.token_urlsafe(32)
        self.budget = Budget(audit)
        transport = urllib.request.build_opener(NoRedirect())
        self.opener = opener or (lambda request: transport.open(request, timeout=120))
        super().__init__(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server_port}/{self.capability}"

    def reconcile(self, token, bound, maximum, response):
        usage = response.get("usage", {})
        keys = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
        if response.get("model") not in SERVED:
            self.budget.blocked = True
            self.budget.record("unexpected_model", id=token)
            return
        try:
            usage = merge_usage({}, usage)
        except Denied as error:
            self.budget.blocked = True
            self.budget.record("unexpected_pricing", id=token, reason=str(error)[:160],
                               usage_shape=usage_shape({"type": "message_start", "message": {"usage": usage}}))
            return
        if not all(integer(usage.get(k)) for k in keys):
            self.budget.record("usage_unknown", id=token)
            return
        cache = usage.get("cache_creation", {})
        if (not isinstance(cache, dict) or set(cache) - {"ephemeral_5m_input_tokens", "ephemeral_1h_input_tokens"}
                or not all(integer(n) for n in cache.values())
                or cache and sum(cache.values()) != usage["cache_creation_input_tokens"]):
            self.budget.blocked = True
            self.budget.record("unexpected_cache_usage", id=token)
            return
        counts = [usage[k] for k in keys]
        if usage.get("output_tokens_details", {}).get("thinking_tokens", 0) > counts[3]:
            self.budget.blocked = True
            self.budget.record("unexpected_output_detail", id=token)
            return
        if sum(counts[:3]) > bound or counts[3] > maximum:
            self.budget.blocked = True
            self.budget.record("bound_breach", id=token)
            return
        amount = GEO * sum((D(n) * rate for n, rate in zip(counts, [D(5), D(10), D("0.5"), D(25)])), D(0)) / MILLION
        self.budget.settle(token, amount)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        return

    def error(self, code, reason):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"type": "error", "error": {"type": "admission_denied", "message": reason}}).encode())

    def do_GET(self):
        self.error(404, "unsupported route")

    def do_POST(self):
        prefix = f"/{self.server.capability}/v1/messages"
        if self.path not in {prefix, prefix + "?beta=true"}:
            self.error(404, "unsupported route")
            return
        raw = b""
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 2000000 or self.headers.get("Transfer-Encoding"):
                raise Denied("unsupported request framing")
            raw = self.rfile.read(length)
            if len(raw) != length or any(beta.strip() not in BETAS
                                         for header in self.headers.get_all("anthropic-beta", [])
                                         for beta in header.split(",")):
                raise Denied("unsupported request mode")
            token, bound, maximum, amount = admission(raw)
        except (ValueError, TypeError, RecursionError, AttributeError):
            self.server.budget.record("invalid_request", sha256=hashlib.sha256(raw).hexdigest())
            self.error(400, "unsupported request shape")
            return
        try:
            self.server.budget.reserve(token, amount, {"sha256": hashlib.sha256(raw).hexdigest(),
                                                      "input_bound": bound, "max_tokens": maximum})
        except Denied:
            self.error(402, "run budget has insufficient unreserved headroom")
            return
        headers = {key: value for key, value in self.headers.items()
                   if key.lower() in {"authorization", "x-api-key", "anthropic-version", "anthropic-beta", "content-type",
                                      "user-agent", "x-app", "x-claude-code-session-id", "anthropic-dangerous-direct-browser-access"}
                   or key.lower().startswith("x-stainless-")}
        route = "/v1/messages" + ("?beta=true" if self.path.endswith("?beta=true") else "")
        request = urllib.request.Request("https://api.anthropic.com" + route, data=raw, headers=headers)
        try:
            upstream = self.server.opener(request)
        except (OSError, urllib.error.HTTPError):
            self.server.budget.record("upstream_error", id=token)
            self.error(502, "upstream request failed; reservation retained")
            return
        self.send_response(upstream.status)
        content_type = upstream.headers.get("Content-Type", "application/json")
        self.send_header("Content-Type", content_type)
        self.end_headers()
        response, wire, complete = {}, bytearray(), False
        try:
            with upstream:
                while chunk := upstream.read1(65536):
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    wire.extend(chunk)
                    if len(wire) > 2000000:
                        raise ValueError("oversized response")
            if "text/event-stream" in content_type:
                response, complete = stream_response(bytes(wire))
            else:
                response, complete = json.loads(wire), True
            if complete and upstream.status == 200:
                self.server.reconcile(token, bound, maximum, response)
            else:
                self.server.budget.record("incomplete", id=token)
        except OSError:
            self.server.budget.record("incomplete", id=token)
        except (ValueError, TypeError, AttributeError) as error:
            self.server.budget.blocked = True
            reason = str(error)[:160] if isinstance(error, Denied) else type(error).__name__
            self.server.budget.record("inconsistent_usage", id=token, reason=reason,
                                     usage_shape=getattr(error, "usage_shape", {"event_type": "unknown"}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", required=True)
    args = parser.parse_args()
    server = Gateway(audit=args.audit)
    print(server.url, flush=True)
    server.serve_forever()
