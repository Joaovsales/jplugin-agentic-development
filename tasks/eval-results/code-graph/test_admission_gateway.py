import importlib.util
import io
import json
from pathlib import Path
import threading
import tempfile
import unittest
import urllib.error
import urllib.request


MODULE = Path(__file__).with_name("admission_gateway.py")
gateway = None
if MODULE.exists():
    spec = importlib.util.spec_from_file_location("admission_gateway", MODULE)
    gateway = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gateway)


def request_body(**changes):
    body = json.loads(Path(__file__).with_name("native-request-shape.json").read_text())
    body.update(changes)
    return json.dumps(body).encode()


def usage(**changes):
    result = {"input_tokens": 20, "output_tokens": 5,
              "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
    result.update(changes)
    return result


class Response(io.BytesIO):
    status = 200

    def __init__(self, body, content_type="application/json"):
        super().__init__(body)
        self.headers = {"Content-Type": content_type}


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(gateway, "admission gateway implementation missing")

    def start(self, opener):
        server = gateway.Gateway(opener=opener)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.server = server
        return server.url

    def post(self, url, body, secret="private-credential"):
        request = urllib.request.Request(url + "/v1/messages", data=body,
                                         headers={"x-api-key": secret})
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            return error.code, error.read()

    def account(self, payload):
        server = gateway.Gateway(opener=lambda request: None)
        self.addCleanup(server.server_close)
        token, bound, maximum, amount = gateway.admission(request_body())
        server.budget.reserve(token, amount, {})
        server.reconcile(token, bound, maximum, payload)
        return server, token

    def test_boundary_and_concurrent_reservations(self):
        budget = gateway.Budget()
        budget.reserve("a", gateway.D("2"), {})
        budget.reserve("b", gateway.D("2"), {})
        with self.assertRaises(gateway.Denied):
            budget.reserve("c", gateway.D("0.000001"), {})
        other = gateway.Budget()
        admitted = []
        barrier = threading.Barrier(10)

        def reserve(index):
            barrier.wait()
            try:
                other.reserve(str(index), gateway.D("0.75"), {})
                admitted.append(index)
            except gateway.Denied:
                pass

        workers = [threading.Thread(target=reserve, args=(i,)) for i in range(10)]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join()
        self.assertEqual(len(admitted), 5)
        self.assertEqual(sum(other.held.values()), gateway.D("3.75"))

    def test_invalid_requests_never_reach_upstream(self):
        forwarded = []
        url = self.start(lambda request: forwarded.append(request))
        invalid = [request_body(model="claude-sonnet-4-6"),
                   request_body(max_tokens=4097),
                   request_body(tools=[{"type": "web_search_20250305", "name": "web_search"}]),
                   request_body(messages=[{"role": "user", "content": [{"type": "image"}]}]),
                   request_body(service_tier="priority"), request_body(speed="fast"),
                   request_body(output_config={"effort": "extreme"}),
                   request_body(unknown_billing_mode=True),
                   request_body(thinking={"type": "enabled", "budget_tokens": 9999}),
                   request_body(messages=[{"role": "user", "content": [
                       {"type": "text", "text": "hello", "cache_control": {"type": "ephemeral", "ttl": "24h"}}]}]),
                   request_body().decode().encode("utf-16")]
        for body in invalid:
            self.assertEqual(self.post(url, body)[0], 400)
        self.assertFalse(forwarded)

    def test_json_settlement_and_secret_redaction(self):
        observed = []
        payload = json.dumps({"model": "claude-opus-4-8", "usage": usage()}).encode()

        def opener(request):
            observed.append((request.full_url, request.get_header("X-api-key")))
            return Response(payload)

        url = self.start(opener)
        self.assertEqual(self.post(url, request_body())[0], 200)
        self.assertEqual(observed, [("https://api.anthropic.com/v1/messages", "private-credential")])
        self.assertEqual(self.server.budget.spent, gateway.D("0.0002475"))
        self.assertFalse(self.server.budget.held)
        audit = json.dumps(self.server.budget.events)
        self.assertNotIn("private-credential", audit)
        self.assertNotIn("Find the caller", audit)
        self.assertIn("sha256", audit)

    def test_stream_passthrough_and_settlement(self):
        cases = json.loads(Path(__file__).with_name("stream-order-cases.json").read_text())
        for name, events in cases.items():
            with self.subTest(name=name):
                wire = b"".join(b"data: " + json.dumps(event).encode() + b"\n\n" for event in events)
                url = self.start(lambda request: Response(wire, "text/event-stream"))
                self.assertEqual(self.post(url, request_body()), (200, wire))
                if name in {"valid", "mapped_start", "normal_blocks"}:
                    self.assertEqual(self.server.budget.spent, gateway.D("0.0002475"))
                    self.assertFalse(self.server.budget.held)
                else:
                    self.assertTrue(self.server.budget.held)
                    self.assertTrue(self.server.budget.blocked)
                    self.assertEqual(self.server.budget.spent, 0)

    def test_partial_stream_retries_keep_each_reservation(self):
        wire = b'data: {"type":"message_start"}\n\n'
        calls = []

        def opener(request):
            calls.append(request)
            return Response(wire, "text/event-stream")

        url = self.start(opener)
        body = request_body(messages=[{"role": "user", "content": "x" * 80000}])
        self.assertEqual(self.post(url, body)[0], 200)
        self.assertEqual(self.post(url, body)[0], 200)
        self.assertEqual(self.post(url, body)[0], 402)
        self.assertEqual(len(calls), 2)
        self.assertEqual(len(self.server.budget.held), 2)

    def test_missing_or_excess_usage_never_releases_reservation(self):
        for payload in [{"model": "claude-opus-5-5"},
                        {"model": "unknown", "usage": usage()},
                        {"model": "claude-opus-5-5", "usage": usage(output_tokens=9999)}]:
            server, token = self.account(payload)
            self.assertIn(token, server.budget.held)

    def test_free_paths_and_capability_protection(self):
        calls = []
        url = self.start(lambda request: calls.append(request) or Response(b"{}"))
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(url.rsplit("/", 1)[0] + "/v1/models")
        self.assertEqual(error.exception.code, 404)
        self.assertEqual(self.post(url, request_body())[0], 200)
        self.assertEqual(len(calls), 1)
        self.assertEqual(self.post(url + "/v1/messages/batches", request_body())[0], 404)

    def test_structural_bounds_and_pricing_union(self):
        body = request_body(messages=[{"role": "user", "content": "é🚢"}],
                            output_config={"effort": "medium"})
        _, bound, maximum, amount = gateway.admission(body)
        self.assertGreater(bound, len(body))
        self.assertEqual(maximum, 4096)
        self.assertEqual(amount, gateway.GEO * (gateway.D(bound) * gateway.D("0.000010")
                         + gateway.D(maximum) * gateway.D("0.000025")))

    def test_cache_usage_settles_at_safe_rate_union(self):
        server, _ = self.account({"model": "claude-opus-5-5", "usage": usage(
            input_tokens=100, cache_creation_input_tokens=200,
            cache_read_input_tokens=300, output_tokens=10)})
        self.assertEqual(server.budget.spent, gateway.D("0.00319"))
        self.assertFalse(server.budget.held)

    def test_upstream_failures_and_redirects_are_not_free_retries(self):
        def opener(request):
            raise urllib.error.URLError("private-credential")

        url = self.start(opener)
        self.assertEqual(self.post(url, request_body())[0], 502)
        self.assertEqual(self.post(url, request_body())[0], 502)
        self.assertEqual(len(self.server.budget.held), 2)
        self.assertNotIn("private-credential", json.dumps(self.server.budget.events))
        self.assertIsNone(gateway.NoRedirect().redirect_request(
            None, None, 302, "redirect", {}, "https://untrusted.invalid/"))

    def test_unknown_response_pricing_keeps_reservation_and_blocks(self):
        for extra in [{"speed": "fast"}, {"inference_geo": "unknown"},
                      {"server_tool_use": {"web_search_requests": 1}},
                      {"service_tier": "priority", "iterations": [{
                          "type": "advisor_message", "model": "claude-fable-5-2",
                          "input_tokens": 100000, "output_tokens": 100000}]},
                      {"future_billable_feature": {"cost_usd": 500}}]:
            server, token = self.account({"model": "claude-opus-5-5", "usage": usage(**extra)})
            self.assertIn(token, server.budget.held)
            self.assertTrue(server.budget.blocked)

    def test_native_beta_route_and_headers(self):
        calls = []
        url = self.start(lambda request: calls.append(request) or Response(b"{}"))
        request = urllib.request.Request(url + "/v1/messages?beta=true", data=request_body(),
                                         headers={"x-app": "cli", "anthropic-beta": Path(__file__).with_name("native-beta-header.txt").read_text().strip()})
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 200)
        self.assertEqual(calls[0].full_url, "https://api.anthropic.com/v1/messages?beta=true")
        self.assertEqual(calls[0].get_header("X-app"), "cli")

    def test_complete_native_request_shape_is_admitted(self):
        for previous in [None, "msg_offline_probe", "44e737ae-217d-4ea1-b556-6d65a28e3985"]:
            _, _, _, amount = gateway.admission(request_body(diagnostics={"previous_message_id": previous}))
            self.assertLess(amount, gateway.D(4))
        for changes in [dict(context_management={"edits": [{"type": "advisor"}]}),
                        dict(thinking={"type": "adaptive", "display": "future_billable_mode"}),
                        dict(system=[{"type": "text", "text": "x", "cache_control": {
                            "type": "ephemeral", "ttl": "1h", "scope": "future"}}]),
                        dict(diagnostics={"previous_message_id": "msg/invalid"}),
                        dict(diagnostics={"previous_message_id": "x" * 257}), dict(diagnostics={"advisor": True})]:
            with self.assertRaises(gateway.Denied):
                gateway.admission(request_body(**changes))

    def test_existing_audit_cannot_reset_a_run_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audit.jsonl"
            budget = gateway.Budget(path)
            budget.reserve("first", gateway.D("1"), {"sha256": "digest"})
            self.assertEqual(json.loads(path.read_text())["held"], "1")
            with self.assertRaises(gateway.Denied):
                gateway.Budget(path)

    def test_pinned_native_delta_placeholders_and_thinking_details(self):
        initial = usage(input_tokens=20, cache_creation_input_tokens=200,
                        cache_read_input_tokens=100, output_tokens=1,
                        cache_creation={"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 200},
                        service_tier="standard", inference_geo="global", speed="standard", iterations=[])
        variants = [
            {"input_tokens": None, "cache_creation_input_tokens": None, "cache_read_input_tokens": None},
            {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
            {"cache_creation": None},
            {"cache_creation": {"ephemeral_5m_input_tokens": None, "ephemeral_1h_input_tokens": 0}},
            {"service_tier": None, "speed": None, "inference_geo": None, "iterations": None, "server_tool_use": None},
            {"output_tokens_details": {"thinking_tokens": 4}, "fallback_credit": None},
            {"output_tokens_details": None},
            {"output_tokens_details": {"thinking_tokens": None}},
        ]
        for update in variants:
            with self.subTest(update=update):
                events = [{"type": "message_start", "message": {"model": "claude-opus-5-5", "usage": initial}},
                          {"type": "message_delta", "usage": update},
                          {"type": "message_delta", "usage": {"output_tokens": 5}}, {"type": "message_stop"}]
                response, complete = gateway.stream_response(b"".join(
                    b"data: " + json.dumps(event).encode() + b"\n\n" for event in events))
                self.assertTrue(complete)
                self.assertEqual(response["usage"]["input_tokens"], 20)
                self.assertEqual(response["usage"]["cache_creation_input_tokens"], 200)
                self.assertEqual(response["usage"]["cache_read_input_tokens"], 100)
                server, token = self.account(response)
                self.assertFalse(server.budget.held)
                self.assertEqual(server.budget.spent, gateway.D("0.0025025"))
        derived = gateway.merge_usage(initial, {"cache_creation_input_tokens": 0,
            "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 300}}, delta=True)
        self.assertEqual(derived["cache_creation_input_tokens"], 300)
        self.assertEqual(derived["cache_creation"]["ephemeral_1h_input_tokens"], 300)
        for update in [{"input_tokens": False}, {"input_tokens": 0.0}, {"input_tokens": 19},
                       {"output_tokens": None}, {"output_tokens": False}, {"output_tokens": 0.0},
                       {"cache_creation": {"ephemeral_1h_input_tokens": False}},
                       {"cache_creation": {"ephemeral_1h_input_tokens": 0.0}},
                       {"unknown_billing_field": None},
                       {"cache_read_input_tokens": 99}, {"fallback_credit": 0},
                       {"fallback_credit": 10}, {"output_tokens_details": {"unknown": 0}},
                       {"output_tokens_details": {"thinking_tokens": False}},
                       {"service_tier": "priority"}, {"iterations": [{"type": "advisor_message"}]}]:
            with self.assertRaises(gateway.Denied):
                gateway.merge_usage(initial, update, delta=True)
        server, token = self.account({"model": "claude-opus-5-5", "usage": usage(
            output_tokens_details={"thinking_tokens": 6})})
        self.assertIn(token, server.budget.held)
        self.assertTrue(server.budget.blocked)

    def test_usage_failure_diagnostics_are_bounded_and_redacted(self):
        secret = "identity-auth-prompt-model-private"
        events = [{"type": "message_start", "message": {"model": "claude-opus-5-5",
                   "content": [{"type": "text", "text": secret}], "usage": usage(output_tokens=1)}},
                  {"type": "message_delta", "usage": {"output_tokens": 5, secret: secret}},
                  {"type": "message_stop"}]
        wire = b"".join(b"data: " + json.dumps(event).encode() + b"\n\n" for event in events)
        url = self.start(lambda request: Response(wire, "text/event-stream"))
        self.post(url, request_body(), secret=secret)
        diagnostic = next(row for row in self.server.budget.events if row["event"] == "inconsistent_usage")
        self.assertIn("reason", diagnostic)
        self.assertEqual(diagnostic["usage_shape"]["event_type"], "message_delta")
        self.assertLessEqual(len(diagnostic["reason"]), 160)
        self.assertNotIn(secret, json.dumps(self.server.budget.events))


if __name__ == "__main__":
    unittest.main()
