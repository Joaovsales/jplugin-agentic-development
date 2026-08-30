#!/usr/bin/env python3
"""A minimal stand-in Jira Cloud REST v2 site, for the Jira adapter's tests.

Real HTTP over a real socket rather than a monkeypatched transport: the seam this
exercises is `urllib` request construction, auth header encoding, status handling
and error-body reading, and a stubbed transport would test none of it.

Deliberately hostile in one respect — when authentication fails it echoes the
`Authorization` header back in the error body, the way a badly written proxy or
debug endpoint does. That is what makes the redaction assertion meaningful: the
credential is genuinely present in the provider's response and must not reach the
user-facing output.

It can also play the two halves of a credential-leaking redirect: `--redirect-to`
answers `/myself` with a 302 to another origin, and `--echo-auth` runs a site that
reports whichever `Authorization` header it was handed. Together they show whether
the client forwards credentials across an origin boundary.

Usage: fake-jira.py <port> [--reject-links] [--no-close-transition]
                           [--redirect-to URL] [--echo-auth]
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

EXPECTED_TOKEN = "fixture-jira-token-abcdef123456"
EXPECTED_EMAIL = "fixture@example.com"

ISSUES = [
    {
        "key": "REG-1",
        "fields": {
            "summary": "Morph live grid recipe",
            "description": (
                "Ship the live grid morph.\n\n"
                "<!-- task-registry:begin -->\n"
                "task-id: recipe.morph-live-grid\n"
                "kind: feature\n"
                "depends-on: recipe.color-lut\n"
                "<!-- task-registry:end -->\n"
            ),
            "status": {"name": "In Progress", "statusCategory": {"key": "indeterminate"}},
            "labels": ["area/render", "now"],
            "issuetype": {"name": "Story"},
            "priority": {"name": "High"},
        },
    },
    {
        "key": "REG-2",
        "fields": {
            "summary": "Colour LUT loader crashes on 8-bit input",
            "description": (
                "<!-- task-registry:begin -->\n"
                "task-id: recipe.color-lut\nkind: bug\n"
                "<!-- task-registry:end -->\n"
            ),
            "status": {"name": "Done", "statusCategory": {"key": "done"}},
            "labels": ["area/color"],
            "issuetype": {"name": "Bug"},
            "priority": {"name": "Medium"},
        },
    },
]


class Handler(BaseHTTPRequestHandler):
    reject_links = False
    close_transition = True
    redirect_to = ""
    echo_auth = False

    def log_message(self, *args):  # silence per-request logging
        pass

    # ------------------------------------------------------------------ helpers
    def _authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        import base64

        try:
            decoded = base64.b64decode(header[6:]).decode("utf-8")
        except Exception:
            return False
        return decoded == f"{EXPECTED_EMAIL}:{EXPECTED_TOKEN}"

    def _send(self, status: int, payload) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _reject(self) -> None:
        # Echoes the credential back on purpose — see the module docstring.
        self._send(
            401,
            {
                "errorMessages": [
                    "Authentication failed. Received header: "
                    + self.headers.get("Authorization", "")
                ]
            },
        )

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    # ------------------------------------------------------------------- routes
    def do_GET(self):
        if self.echo_auth:
            # Stands in for whatever a redirect target might be. Reports what it
            # was given rather than requiring credentials, so the test can tell
            # "header was forwarded" from "header was stripped".
            return self._send(
                200, {"received_authorization": self.headers.get("Authorization", "")}
            )
        if self.redirect_to and self.path.split("?")[0].endswith("/myself"):
            self.send_response(302)
            self.send_header("Location", self.redirect_to)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        if not self._authorized():
            return self._reject()
        path = self.path.split("?")[0]
        if path.endswith("/myself"):
            return self._send(200, {"accountId": "fixture", "emailAddress": EXPECTED_EMAIL})
        if path.endswith("/search"):
            return self._send(200, {"issues": ISSUES, "total": len(ISSUES)})
        if path.endswith("/transitions"):
            transitions = (
                [{"id": "31", "name": "Done", "to": {"statusCategory": {"key": "done"}}}]
                if self.close_transition
                else [{"id": "11", "name": "Back to To Do", "to": {"statusCategory": {"key": "new"}}}]
            )
            return self._send(200, {"transitions": transitions})
        for issue in ISSUES:
            if path.endswith("/issue/" + issue["key"]):
                return self._send(200, issue)
        return self._send(404, {"errorMessages": ["Issue does not exist"]})

    def do_POST(self):
        if not self._authorized():
            return self._reject()
        path = self.path.split("?")[0]
        payload = self._read_body()
        if path.endswith("/issueLink"):
            if self.reject_links:
                return self._send(
                    400, {"errorMessages": ["No issue link type with name 'Blocks' found"]}
                )
            return self._send(201, {})
        if path.endswith("/transitions"):
            return self._send(204, {})
        if path.endswith("/comment"):
            return self._send(201, {"id": "10000"})
        if path.endswith("/issue"):
            summary = payload.get("fields", {}).get("summary", "")
            return self._send(201, {"key": "REG-99", "id": "10099", "summary": summary})
        return self._send(404, {"errorMessages": ["Unknown endpoint"]})

    def do_PUT(self):
        if not self._authorized():
            return self._reject()
        payload = self._read_body()
        if self.reject_links and "parent" in payload.get("fields", {}):
            return self._send(
                400, {"errorMessages": ["Field 'parent' cannot be set on this issue type"]}
            )
        return self._send(204, {})


def main() -> int:
    port = int(sys.argv[1])
    Handler.reject_links = "--reject-links" in sys.argv
    Handler.close_transition = "--no-close-transition" not in sys.argv
    Handler.echo_auth = "--echo-auth" in sys.argv
    if "--redirect-to" in sys.argv:
        Handler.redirect_to = sys.argv[sys.argv.index("--redirect-to") + 1]
    server = HTTPServer(("127.0.0.1", port), Handler)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
