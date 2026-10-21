#!/usr/bin/env python3
"""Seeded fixture generator for the read-shunt suite.

Usage: fixture_gen.py <case-name> --out <dir>

One deterministic generator per case, one fixed seed per case. Fixtures are
generated into the run workspace and never committed, so nothing in a
candidate's checkout names the suite, and two runs of one case read
byte-identical files. Hidden reference answers (the bug lines, the traceback
location, the stale callers) live in this file and nowhere the candidate reads.

Stdlib only. Prints nothing on success.
"""
import argparse
import datetime
import json
import os
import sys
import random

def write(out, rel, text):
    """Write text (LF endings, UTF-8) under out, creating parent directories."""
    path = os.path.join(out, *rel.split("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text if text.endswith("\n") else text + "\n")


def snake(name):
    out = []
    for i, ch in enumerate(name):
        if ch.isupper() and i:
            out.append("_")
        out.append(ch.lower())
    return "".join(out)


# --- 1. billing-client-zero-total ---------------------------------------------

BILLING_NOUNS = [
    "Customer", "Plan", "Coupon", "Subscription", "Payment", "Refund", "Dispute",
    "Payout", "Levy", "Address", "Product", "Price", "Meter", "Usage", "Credit",
    "Balance", "Mandate", "Quote", "Schedule", "Webhook", "Account", "Contact",
    "Receipt", "Ledger", "Charge", "Transfer", "Session", "Event", "Report",
    "Tier", "Allocation", "Adjustment", "Settlement", "Statement", "Fee",
    "Invoice",
]
BILLING_SUFFIXES = ["", "Item", "Detail"]
BILLING_FIELDS = [
    ("id", "str", '""'), ("name", "str", '""'), ("status", "str", '""'),
    ("created_at", "str", '""'), ("updated_at", "str", '""'),
    ("metadata", "Dict[str, Any]", "field(default_factory=dict)"),
    ("note", "Optional[str]", "None"), ("active", "bool", "True"),
    ("quantity", "int", "0"), ("rate", "float", "0.0"),
    ("labels", "List[str]", "field(default_factory=list)"),
    ("reference", "Optional[str]", "None"), ("kind", "str", '""'),
    ("owner_id", "str", '""'), ("region", "Optional[str]", "None"),
    ("version", "int", "1"),
]


def billing_model(rng, name):
    fields = rng.sample(BILLING_FIELDS, 12)
    lines = ["@dataclass", "class %s:" % name, '    """%s resource as returned by the billing API."""' % name, ""]
    for fname, ftype, default in fields:
        lines.append("    %s: %s = %s" % (fname, ftype, default))
    lines += ["", "    @classmethod", '    def from_payload(cls, payload: Dict[str, Any]) -> "%s":' % name,
              '        """Build a %s from a decoded JSON payload."""' % name, "        return cls("]
    for fname, ftype, default in fields:
        fallback = default if not default.startswith("field(") else ("{}" if "dict" in default else "[]")
        lines.append('            %s=payload.get("%s", %s),' % (fname, fname, fallback))
    lines += ["        )", "", ""]
    return lines


def billing_api(noun):
    s = snake(noun)
    plural = s + "s"
    lines = ["class %sApi(_Resource):" % noun, '    """Endpoints for %s."""' % plural, ""]
    lines += [
        "    def list_%s(self, limit: int = 25, cursor: Optional[str] = None) -> List[%s]:" % (plural, noun),
        '        """List %s, newest first."""' % plural,
        "        params: Dict[str, Any] = {\"limit\": limit}",
        "        if cursor is not None:",
        "            params[\"cursor\"] = cursor",
        "        payload = self._request(\"GET\", \"/v1/%s\", params=params)" % plural,
        "        return [%s.from_payload(item) for item in payload.get(\"data\", [])]" % noun,
        "",
    ]
    if noun != "Invoice":
        lines += [
            "    def get_%s(self, %s_id: str) -> %s:" % (s, s, noun),
            '        """Fetch one %s by id."""' % s,
            "        payload = self._request(\"GET\", \"/v1/%s/\" + %s_id)" % (plural, s),
            "        return %s.from_payload(payload)" % noun,
            "",
        ]
    lines += [
        "    def create_%s(self, body: Dict[str, Any]) -> %s:" % (s, noun),
        '        """Create a %s."""' % s,
        "        payload = self._request(\"POST\", \"/v1/%s\", body=body)" % plural,
        "        return %s.from_payload(payload)" % noun,
        "",
        "    def update_%s(self, %s_id: str, body: Dict[str, Any]) -> %s:" % (s, s, noun),
        '        """Update a %s."""' % s,
        "        payload = self._request(\"PATCH\", \"/v1/%s/\" + %s_id, body=body)" % (plural, s),
        "        return %s.from_payload(payload)" % noun,
        "",
        "    def delete_%s(self, %s_id: str) -> None:" % (s, s),
        '        """Delete a %s."""' % s,
        "        self._request(\"DELETE\", \"/v1/%s/\" + %s_id)" % (plural, s),
        "",
        "",
    ]
    return lines


INVOICE_BLOCK = '''@dataclass
class Invoice:
    """Invoice resource as returned by the billing API."""

    id: str = ""
    number: str = ""
    currency: str = "usd"
    total: float = 0.0
    status: str = ""
    customer_id: str = ""
    created_at: str = ""


def parse_invoice(payload: Dict[str, Any]) -> Invoice:
    """Build an Invoice from a decoded JSON payload."""
    amount = payload.get("total", 0)
    currency = payload.get("currency", "usd")
    number = payload.get("number", "")
    return Invoice(
        id=payload.get("id", ""),
        number=number,
        currency=currency,
        total=amount,
        status=payload.get("status", ""),
        customer_id=payload.get("customer_id", ""),
        created_at=payload.get("created_at", ""),
    )


class InvoiceApi(_Resource):
    """Endpoints for invoices."""

    def list_invoices(self, limit: int = 25, cursor: Optional[str] = None) -> List[Invoice]:
        """List invoices, newest first."""
        params: Dict[str, Any] = {"limit": limit}
        if cursor is not None:
            params["cursor"] = cursor
        payload = self._request("GET", "/v1/invoices", params=params)
        return [parse_invoice(item) for item in payload.get("data", [])]

    def get_invoice(self, invoice_id: str) -> Invoice:
        """Fetch one invoice by id."""
        payload = self._request("GET", "/v1/invoices/" + invoice_id)
        return parse_invoice(payload)

    def void_invoice(self, invoice_id: str) -> Invoice:
        """Void an invoice."""
        payload = self._request("POST", "/v1/invoices/" + invoice_id + "/void")
        return parse_invoice(payload)


'''

BILLING_HEADER = '''"""Billing API client (generated from the OpenAPI document, do not edit by hand)."""
from __future__ import annotations

import json
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


class ApiError(Exception):
    """Raised when the billing API answers with a non-2xx status."""

    def __init__(self, status: int, message: str) -> None:
        super().__init__("%d: %s" % (status, message))
        self.status = status
        self.message = message


class _Resource:
    """Shared plumbing for every endpoint group."""

    def __init__(self, base_url: str, token: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._token = token

    def _request(self, method: str, path: str, params: Optional[Dict[str, Any]] = None,
                 body: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        url = self._base_url + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", "Bearer " + self._token)
        request.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(request) as response:
            raw = response.read().decode("utf-8")
        return json.loads(raw) if raw else {}


'''


def gen_billing(out, rng):
    sections = []
    for noun in BILLING_NOUNS:
        sec = []
        if noun != "Invoice":
            sec += billing_model(rng, noun)
        for suffix in BILLING_SUFFIXES[1:]:
            sec += billing_model(rng, noun + suffix)
        if noun == "Invoice":
            sec += INVOICE_BLOCK.split("\n")[:-1]
        else:
            sec += billing_api(noun)
        sections.append(sec)
    # The invoice section sits mid-file, where a reader has to go and find it.
    inv = sections.pop(BILLING_NOUNS.index("Invoice"))
    sections.insert(len(sections) // 2 + 3, inv)
    lines = BILLING_HEADER.split("\n")[:-1]
    for sec in sections:
        lines += sec
    lines += ["class BillingClient:", '    """Entry point: one attribute per endpoint group."""', "",
              "    def __init__(self, base_url: str, token: str) -> None:"]
    for noun in BILLING_NOUNS:
        lines.append("        self.%s = %sApi(base_url, token)" % (snake(noun) + "s", noun))
    write(out, "billing_client.py", "\n".join(lines))
    write(out, "samples/invoice_response.json", json.dumps({
        "id": "inv_8f2c41", "number": "INV-2041", "currency": "usd", "status": "paid",
        "customer_id": "cus_3a91d0", "created_at": "2026-02-03T09:14:00Z",
        "total_cents": 12900, "subtotal_cents": 10750, "tax_cents": 2150,
    }, indent=2))


# --- 2. nightly-pipeline-failure -----------------------------------------------

LOG_PACKAGES = ["requests", "boto3", "pydantic", "click", "jinja2", "pyyaml", "attrs", "urllib3",
                "cryptography", "sqlalchemy", "redis", "orjson", "tqdm", "rich", "httpx"]
LOG_MODULES = ["ingest", "catalog", "billing", "search", "export", "auth", "notify", "sync", "report", "schedule"]
LOG_CHECKS = ["handles_empty_input", "rejects_bad_token", "retries_on_timeout", "keeps_order", "parses_dates",
              "paginates", "closes_handles", "maps_errors", "trims_whitespace", "caches_lookup"]


def gen_log(out, rng):
    start = datetime.datetime(2026, 3, 14, 2, 0, 0)
    t = [start]
    lines = []

    def emit(text):
        t[0] += datetime.timedelta(seconds=rng.choice([0, 0, 0, 1, 1, 2]))
        lines.append("%s %s" % (t[0].strftime("%Y-%m-%dT%H:%M:%SZ"), text))

    emit("[runner] job nightly-pipeline #48213 started on build-agent-07")
    emit("[runner] checkout 9c1e4f2 (main)")
    target = 20150
    step = 0
    while len(lines) < target:
        kind = rng.random()
        if kind < 0.18:
            step += 1
            emit("[step %02d/32] %s" % (min(step // 600 + 1, 30), rng.choice(["restoring cache", "resolving dependencies", "building wheels", "linting sources", "running checks", "packaging artifacts"])))
        elif kind < 0.40:
            emit("[pip] Collecting %s==%d.%d.%d" % (rng.choice(LOG_PACKAGES), rng.randint(1, 9), rng.randint(0, 30), rng.randint(0, 9)))
        elif kind < 0.55:
            emit("[pip]   Using cached %s-%d.%d.%d-py3-none-any.whl (%d kB)" % (rng.choice(LOG_PACKAGES), rng.randint(1, 9), rng.randint(0, 30), rng.randint(0, 9), rng.randint(20, 900)))
        elif kind < 0.85:
            mod = rng.choice(LOG_MODULES)
            emit("[pytest] checks/check_%s.py::check_%s PASSED [%3d%%]" % (mod, rng.choice(LOG_CHECKS), rng.randint(1, 100)))
        elif kind < 0.93:
            emit("[docker] Layer %s: Pull complete" % "".join(rng.choice("0123456789abcdef") for _ in range(12)))
        elif kind < 0.98:
            emit("[net] WARN retrying GET https://pypi.internal/simple/%s/ (attempt %d/3)" % (rng.choice(LOG_PACKAGES), rng.randint(1, 2)))
        else:
            emit("[net] ERROR transient 503 from artifact cache, falling back to origin (ignored)")
    emit("[step 31/32] publish release manifest")
    emit("[deploy] resolving manifest for channel=stable")
    emit("[deploy] writing manifest to s3://release-artifacts/nightly/manifest.json")
    tb = [
        "Traceback (most recent call last):",
        '  File "/builds/app/deploy/cli.py", line 88, in main',
        "    release.publish_manifest(manifest, destination)",
        '  File "/builds/app/deploy/release.py", line 212, in publish_manifest',
        '    tag = manifest["release_tag"]',
        "KeyError: 'release_tag'",
    ]
    lines.extend(tb)
    emit("[runner] step 31/32 failed with exit code 1")
    emit("[runner] uploading job log (%d lines)" % len(lines))
    emit("[runner] cleaning up workspace")
    emit("[runner] job nightly-pipeline #48213 finished: FAILED")
    write(out, "ci-run-48213.log", "\n".join(lines))


# --- 3. catalog-currency-field --------------------------------------------------

CATALOG_MODELS = '''"""Catalog data model."""
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional


@dataclass
class Dimensions:
    """Physical size of a packed product, in millimetres."""

    width_mm: int = 0
    height_mm: int = 0
    depth_mm: int = 0

    def volume_cm3(self) -> float:
        return (self.width_mm * self.height_mm * self.depth_mm) / 1000.0


@dataclass
class Supplier:
    """Company that supplies a product."""

    id: str
    name: str
    country: str = "US"
    lead_time_days: int = 14

    def to_dict(self) -> Dict[str, object]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, object]) -> "Supplier":
        return cls(
            id=str(data["id"]),
            name=str(data["name"]),
            country=str(data.get("country", "US")),
            lead_time_days=int(data.get("lead_time_days", 14)),
        )


@dataclass
class Product:
    """A sellable catalog entry."""

    id: str
    sku: str
    name: str
    price: float
    category: str = "general"
    tags: List[str] = field(default_factory=list)
    weight_g: int = 0
    in_stock: bool = True
    dimensions: Optional[Dimensions] = None

    def to_dict(self) -> Dict[str, object]:
        data = asdict(self)
        if self.dimensions is None:
            data.pop("dimensions")
        return data

    @classmethod
    def from_dict(cls, data: Dict[str, object]) -> "Product":
        dims = data.get("dimensions")
        return cls(
            id=str(data["id"]),
            sku=str(data["sku"]),
            name=str(data["name"]),
            price=float(data["price"]),
            category=str(data.get("category", "general")),
            tags=list(data.get("tags", [])),
            weight_g=int(data.get("weight_g", 0)),
            in_stock=bool(data.get("in_stock", True)),
            dimensions=Dimensions(**dims) if dims else None,
        )

    def display_price(self) -> str:
        return "%.2f" % self.price


@dataclass
class Category:
    """A node in the category tree."""

    id: str
    name: str
    parent_id: Optional[str] = None

    def is_root(self) -> bool:
        return self.parent_id is None


@dataclass
class InventoryRecord:
    """Stock level of one product in one warehouse."""

    product_id: str
    warehouse: str
    on_hand: int = 0
    reserved: int = 0

    def available(self) -> int:
        return max(self.on_hand - self.reserved, 0)


class Catalog:
    """In-memory view over a list of products."""

    def __init__(self, products: List[Product]) -> None:
        self._by_id: Dict[str, Product] = {p.id: p for p in products}

    def __len__(self) -> int:
        return len(self._by_id)

    def get(self, product_id: str) -> Optional[Product]:
        return self._by_id.get(product_id)

    def in_category(self, category: str) -> List[Product]:
        return [p for p in self._by_id.values() if p.category == category]

    def tagged(self, tag: str) -> List[Product]:
        return [p for p in self._by_id.values() if tag in p.tags]

    def cheapest(self, count: int = 5) -> List[Product]:
        return sorted(self._by_id.values(), key=lambda p: p.price)[:count]

    def to_list(self) -> List[Dict[str, object]]:
        return [p.to_dict() for p in self._by_id.values()]
'''

CATALOG_WORDS = ["Anvil", "Beacon", "Cobalt", "Dune", "Ember", "Fjord", "Garnet", "Harbor", "Ivory", "Juniper",
                 "Kestrel", "Lantern", "Meadow", "Nimbus", "Onyx", "Prism", "Quartz", "Ridge", "Summit", "Thistle"]
CATALOG_KINDS = ["Lamp", "Chair", "Kettle", "Shelf", "Backpack", "Bottle", "Notebook", "Speaker", "Mug", "Rug"]
CATALOG_CATS = ["home", "kitchen", "office", "outdoor", "audio", "travel", "decor"]
CATALOG_TAGS = ["new", "sale", "eco", "gift", "bestseller", "limited", "bundle", "premium"]


def gen_catalog(out, rng):
    write(out, "models.py", CATALOG_MODELS)
    products = []
    for i in range(2200):
        item = {
            "id": "p%05d" % i,
            "sku": "SKU-%04d-%s" % (rng.randint(0, 9999), rng.choice("ABCDEFGH")),
            "name": "%s %s" % (rng.choice(CATALOG_WORDS), rng.choice(CATALOG_KINDS)),
            "price": round(rng.uniform(2, 480), 2),
            "category": rng.choice(CATALOG_CATS),
            "tags": rng.sample(CATALOG_TAGS, rng.randint(0, 3)),
            "weight_g": rng.randint(40, 9000),
            "in_stock": rng.random() < 0.8,
        }
        products.append(item)
    write(out, "fixtures/catalog.json", json.dumps(products, indent=2))


# --- 4. orders-extract-tax --------------------------------------------------------

ORDER_VERBS = ["validate", "summarise", "label", "reserve", "audit", "route", "notify", "archive", "refund", "split"]
ORDER_NOUNS = ["retail", "wholesale", "pickup", "express", "gift", "backorder", "subscription", "preorder", "return", "bundle"]
ORDER_KEYS = ["customer_id", "region", "channel", "currency_hint", "coupon", "carrier", "warehouse", "priority", "note", "placed_at"]

COMPUTE_TOTALS = '''def compute_totals(order):
    """Return subtotal, tax and total for an order."""
    subtotal = 0.0
    for line in order["lines"]:
        subtotal += line["qty"] * line["unit_price"]
    region = order.get("region", "US")
    if region == "EU":
        tax = subtotal * 0.21
    elif region == "UK":
        tax = subtotal * 0.20
    elif region == "CA":
        tax = subtotal * 0.13
    elif region == "AU":
        tax = subtotal * 0.10
    else:
        tax = subtotal * 0.07
    tax = round(tax, 2)
    total = round(subtotal + tax, 2)
    return {"subtotal": round(subtotal, 2), "tax": tax, "total": total}
'''


def order_function(rng, name, calls_totals):
    lines = ["def %s(order):" % name, '    """Step %s of the order flow."""' % name.replace("_", " "),
             '    lines = order.get("lines", [])', "    if not lines:", '        raise ValueError("order has no lines")']
    if calls_totals:
        lines += ["    totals = compute_totals(order)", '    if totals["total"] <= 0:', '        raise ValueError("order total must be positive")']
    for key in rng.sample(ORDER_KEYS, rng.randint(7, 10)):
        lines += ['    %s = order.get("%s")' % (key, key), "    if %s is None:" % key,
                  '        order["%s"] = %s' % (key, rng.choice(['""', "0", "[]", '"unset"'])),
                  "    elif not isinstance(%s, (str, int, list)):" % key,
                  '        raise TypeError("%s has an unsupported type")' % key]
    for _ in range(rng.randint(3, 5)):
        lines += ["    for line in lines:", '        if line["qty"] > %d:' % rng.randint(50, 500),
                  '            line["flag"] = "%s"' % rng.choice(["bulk", "review", "split", "hold"])]
    lines += ["    order[\"stage\"] = \"%s\"" % name, "    return order", "", ""]
    return lines


def gen_orders(out, rng):
    names = set()
    while len(names) < 46:
        names.add("%s_%s_%s" % (rng.choice(ORDER_VERBS), rng.choice(ORDER_NOUNS), rng.choice(["flow", "step", "pass"])))
    names = sorted(names)
    rng.shuffle(names)
    callers = set(rng.sample(range(len(names)), 15))
    blocks = [order_function(rng, n, i in callers) for i, n in enumerate(names)]
    blocks.insert(len(blocks) // 3, COMPUTE_TOTALS.split("\n") + ["", ""])
    lines = ['"""Order processing."""', "", ""]
    for b in blocks:
        lines += b
    write(out, "orders.py", "\n".join(lines))


# --- 5. pipeline-checks-intermittent -----------------------------------------------

CHECKS_HELPERS = '''"""Verification checks for the ingest pipeline."""
from dataclasses import dataclass
from typing import List


@dataclass
class Entry:
    order_id: str
    weight: int


@dataclass
class Batch:
    entries: List[Entry]
    order_ids: List[str]


def make_batch(ids):
    """Build a batch whose order_ids keep the submission order."""
    entries = [Entry(order_id=i, weight=len(i)) for i in ids]
    return Batch(entries=entries, order_ids=list(ids))


'''

BATCH_CHECK = '''def check_batch_order():
    """The batch reports ids in the order they were submitted."""
    batch = make_batch(["ord-%d" % n for n in range(12)])
    seen = {entry.order_id for entry in batch.entries}
    assert list(seen) == batch.order_ids


'''

CHECK_NOUNS = ["window", "bucket", "queue", "ledger", "cursor", "shard", "buffer", "index", "lease", "token", "digest", "slot"]
CHECK_ASPECTS = ["bounds", "totals", "spread", "offsets", "ranges", "steps", "gaps", "limits"]


def gen_checks(out, rng):
    names = set()
    while len(names) < 125:
        names.add("%s_%s_%s" % (rng.choice(CHECK_NOUNS), rng.choice(CHECK_ASPECTS), rng.randint(1, 99)))
    names = sorted(names)
    rng.shuffle(names)
    blocks = []
    for n in names:
        vals = [rng.randint(1, 90) for _ in range(rng.randint(5, 8))]
        lines = ["def check_%s():" % n, '    """The %s stays inside its limits."""' % n.replace("_", " "),
                 "    values = %s" % vals, "    total = sum(values)", "    assert total == %d" % sum(vals),
                 "    assert max(values) == %d" % max(vals), "    assert min(values) == %d" % min(vals),
                 "    ordered = sorted(values)", "    assert ordered[0] == %d" % min(vals),
                 "    assert ordered[-1] == %d" % max(vals), "    assert len(values) == %d" % len(vals),
                 "    half = total // 2", "    assert half * 2 <= total", "", ""]
        blocks.append("\n".join(lines))
    blocks.insert(len(blocks) // 2, BATCH_CHECK.rstrip("\n") + "\n\n")
    write(out, "verify_pipeline.py", CHECKS_HELPERS + "\n".join(blocks))


# --- 6. settings-loader-port ---------------------------------------------------------

SETTINGS_HEAD = r"""'use strict';
/**
 * Settings loader.
 *
 * Precedence, highest first: environment variable, file value, built-in default.
 * An environment variable that is set to the empty string counts as unset.
 * String values may reference other settings as ${NAME} or ${NAME:-fallback};
 * references resolve against the environment first, then against the file.
 */
const fs = require('fs');

class SettingsError extends Error {
  constructor(message) {
    super(message);
    this.name = 'SettingsError';
  }
}

function readFileValues(filePath) {
  if (!filePath) {
    return {};
  }
  let raw;
  try {
    raw = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') {
      return {};
    }
    throw err;
  }
  return JSON.parse(raw);
}

function lookupPath(object, dotted) {
  let current = object;
  for (const part of dotted.split('.')) {
    if (current === null || typeof current !== 'object' || !(part in current)) {
      return undefined;
    }
    current = current[part];
  }
  return current;
}

function interpolate(value, env, fileValues) {
  if (typeof value !== 'string') {
    return value;
  }
  return value.replace(/\$\{([A-Za-z0-9_.]+)(?::-([^}]*))?\}/g, (match, name, fallback) => {
    const fromEnv = env[name];
    if (fromEnv !== undefined && fromEnv !== '') {
      return fromEnv;
    }
    const fromFile = lookupPath(fileValues, name);
    if (fromFile !== undefined) {
      return String(fromFile);
    }
    if (fallback !== undefined) {
      return fallback;
    }
    throw new SettingsError('unresolved reference ' + match);
  });
}

function coerce(raw, type, label) {
  if (type === 'int') {
    if (typeof raw === 'number') {
      return raw;
    }
    if (String(raw).search(/^-?\d+$/) === -1) {
      throw new SettingsError(label + ' must be an integer');
    }
    return parseInt(raw, 10);
  }
  if (type === 'bool') {
    if (typeof raw === 'boolean') {
      return raw;
    }
    const text = String(raw).toLowerCase();
    if (['1', 'true', 'yes', 'on'].includes(text)) {
      return true;
    }
    if (['0', 'false', 'no', 'off'].includes(text)) {
      return false;
    }
    throw new SettingsError(label + ' must be a boolean');
  }
  return String(raw);
}

function resolveOne(definition, env, fileValues) {
  const fromEnv = env[definition.env];
  if (fromEnv !== undefined && fromEnv !== '') {
    return { source: 'env', value: coerce(interpolate(fromEnv, env, fileValues), definition.type, definition.fileKey) };
  }
  const fromFile = lookupPath(fileValues, definition.fileKey);
  if (fromFile !== undefined) {
    return { source: 'file', value: coerce(interpolate(fromFile, env, fileValues), definition.type, definition.fileKey) };
  }
  return { source: 'default', value: definition.default };
}

function loadSettings(options) {
  const env = (options && options.env) || process.env;
  const fileValues = readFileValues(options && options.file);
  const result = {};
  const sources = {};
  for (const name of Object.keys(SETTINGS)) {
    const definition = SETTINGS[name];
    const resolved = resolveOne(definition, env, fileValues);
    result[name] = definition.validate(resolved.value);
    sources[name] = resolved.source;
  }
  Object.defineProperty(result, 'sources', { value: Object.freeze(sources), enumerable: false });
  return Object.freeze(result);
}

const SETTINGS = {
"""

SETTINGS_TAIL = """};

module.exports = { loadSettings, SettingsError, SETTINGS };
"""

SETTING_GROUPS = {
    "http": ["timeoutMs", "maxRedirects", "userAgent", "keepAlive", "proxyUrl", "retryLimit", "retryDelayMs", "poolSize", "compression"],
    "db": ["host", "port", "name", "poolMin", "poolMax", "statementTimeoutMs", "sslMode", "schema", "readReplica"],
    "cache": ["ttlSeconds", "maxEntries", "namespace", "enabled", "warmOnStart", "evictionPolicy", "host", "port", "compress"],
    "queue": ["url", "visibilityTimeoutS", "maxBatch", "deadLetterAfter", "pollIntervalMs", "prefix", "fifo", "region", "concurrency"],
    "auth": ["issuer", "audience", "tokenTtlS", "refreshTtlS", "clockSkewS", "cookieName", "secureCookies", "jwksUrl", "algorithm"],
    "log": ["level", "format", "destination", "sampleRate", "includeStack", "redactFields", "maxLineBytes", "rotateMb", "color"],
    "mail": ["host", "port", "from", "replyTo", "useTls", "timeoutMs", "maxRecipients", "templateDir", "dryRun"],
    "storage": ["bucket", "region", "prefix", "multipartMb", "publicUrl", "encrypt", "retention", "cdnUrl", "tempDir"],
    "metrics": ["enabled", "endpoint", "intervalS", "prefix", "tags", "histogramBuckets", "timeoutMs", "batchSize", "protocol"],
    "feature": ["newCheckout", "darkMode", "betaApi", "exportV2", "fastSearch", "inlineHelp", "autoRetry", "auditTrail", "softDelete"],
}
SETTING_TYPES = ["int", "string", "bool"]


def setting_entry(rng, group, key):
    name = "%s_%s" % (group, key)
    env = "APP_%s_%s" % (group.upper(), "".join(("_" + c if c.isupper() else c) for c in key).upper())
    kind = rng.choice(SETTING_TYPES)
    label = "%s.%s" % (group, key)
    lines = ["  %s: {" % name, "    env: '%s'," % env, "    fileKey: '%s'," % label]
    if kind == "int":
        lo, hi = 0, rng.choice([100, 1000, 65535, 86400])
        lines += ["    type: 'int',", "    default: %d," % rng.randint(lo + 1, hi // 2 + 1), "    validate(value) {",
                  "      if (!Number.isInteger(value)) {", "        throw new SettingsError('%s must be an integer');" % label,
                  "      }", "      if (value < %d || value > %d) {" % (lo, hi),
                  "        throw new SettingsError('%s must be between %d and %d');" % (label, lo, hi),
                  "      }", "      return value;", "    },"]
    elif kind == "bool":
        lines += ["    type: 'bool',", "    default: %s," % rng.choice(["true", "false"]), "    validate(value) {",
                  "      if (typeof value !== 'boolean') {", "        throw new SettingsError('%s must be a boolean');" % label,
                  "      }", "      return value;", "    },"]
    else:
        allowed = rng.sample(["alpha", "beta", "gamma", "delta", "omega", "plain", "strict"], 3)
        lines += ["    type: 'string',", "    default: '%s'," % allowed[0], "    validate(value) {",
                  "      if (typeof value !== 'string' || value.length === 0) {",
                  "        throw new SettingsError('%s must be a non-empty string');" % label, "      }",
                  "      if (!%s.includes(value)) {" % json.dumps(allowed).replace('"', "'"),
                  "        throw new SettingsError('%s must be one of %s');" % (label, ", ".join(allowed)),
                  "      }", "      return value;", "    },"]
    lines.append("  },")
    return lines


def gen_settings(out, rng):
    lines = SETTINGS_HEAD.split("\n")[:-1]
    for group, keys in SETTING_GROUPS.items():
        for key in keys:
            lines += setting_entry(rng, group, key)
    lines += SETTINGS_TAIL.split("\n")[:-1]
    write(out, "reference/settings_loader.js", "\n".join(lines))


# --- 7. load-record-callers ----------------------------------------------------------

SVC_CORE = '''"""Record access for the svc package."""


class RecordNotFound(KeyError):
    """Raised when a record key is absent from the store."""


def load_record(store, key):
    """Return the record stored under key."""
    try:
        return store[key]
    except KeyError:
        raise RecordNotFound(key)


def record_exists(store, key):
    return key in store
'''

SVC_TOPICS = ["invoice", "member", "booking", "shipment", "ticket", "device", "policy", "venue", "coupon", "profile"]
SVC_ACTIONS = ["summary", "status", "owner", "history", "limits", "labels"]


def svc_module(rng, index, mode):
    topic = SVC_TOPICS[index % len(SVC_TOPICS)]
    lines = ['"""Service module %02d: %s helpers."""' % (index, topic)]
    if mode == "stale":
        lines.append("from svc.core import fetch_record")
    elif mode == "fresh":
        lines.append("from svc.core import load_record")
    lines += ["", ""]
    count = rng.randint(5, 8)
    for n in range(count):
        action = SVC_ACTIONS[n % len(SVC_ACTIONS)]
        fn = "%s_%s_%d" % (topic, action, index)
        lines += ["def %s(store, key):" % fn, '    """Return the %s of a %s."""' % (action, topic)]
        if mode == "stale" and n < 2:
            lines += ["    record = fetch_record(store, key)"]
        elif mode == "fresh" and n < 2:
            lines += ["    record = load_record(store, key)"]
        else:
            lines += ["    record = store.get(key, {})"]
        lines += ['    value = record.get("%s", "")' % action, "    if not value:", '        return "%s unavailable"' % action,
                  "    return str(value).strip()", "", ""]
    text = "\n".join(lines).rstrip("\n") + "\n"
    n_lines = text.count("\n")
    if not 40 <= n_lines <= 80:
        raise SystemExit("svc module %d has %d lines" % (index, n_lines))
    return text


def gen_svc(out, rng):
    write(out, "svc/core.py", SVC_CORE)
    write(out, "svc/__init__.py", '"""Service package."""')
    pool = [i for i in range(1, 41) if i not in (7, 12)]
    stale = set([7] + rng.sample(pool, 22))
    rest = [i for i in range(1, 41) if i not in stale]
    plain = set(rng.sample([i for i in rest if i != 12], 5))
    for i in range(1, 41):
        mode = "stale" if i in stale else ("plain" if i in plain else "fresh")
        write(out, "svc/mod_%02d.py" % i, svc_module(rng, i, mode))


# --- 8. changelog-release-notes ---------------------------------------------------------

CL_AREAS = ["importer", "scheduler", "exporter", "dashboard", "search index", "audit log", "notification service",
            "permissions model", "billing connector", "mobile API", "report builder", "webhook dispatcher"]
CL_ADDED = ["Added %s support for CSV and JSON bulk operations.", "Added a configurable retry limit to the %s.",
            "Added per-workspace defaults to the %s.", "Added keyboard shortcuts to the %s.",
            "Added a dry-run mode to the %s.", "Added structured error codes to the %s."]
CL_CHANGED = ["Changed the %s to batch writes in groups of 500.", "Changed the default timeout of the %s to 30 seconds.",
              "Changed the %s output to sort deterministically.", "Changed the %s to read settings once at start.",
              "Changed the %s to log one line per request."]
CL_FIXED = ["Fixed a crash in the %s when a field was missing.", "Fixed duplicate entries produced by the %s after a retry.",
            "Fixed the %s dropping the last item of a page.", "Fixed a race in the %s during shutdown.",
            "Fixed incorrect pagination in the %s.", "Fixed the %s ignoring the locale of the workspace."]
CL_REMOVED = ["Removed the legacy v1 endpoints of the %s.", "Removed the deprecated --fast flag from the %s.",
              "Removed support for the old config format in the %s."]
CL_SECTIONS = [("Added", CL_ADDED), ("Changed", CL_CHANGED), ("Fixed", CL_FIXED), ("Removed", CL_REMOVED)]


def gen_changelog(out, rng):
    lines = ["# Changelog", "", "All notable changes to this project are documented here.", "",
             "The format follows Keep a Changelog; versions follow Semantic Versioning.", ""]
    date = datetime.date(2026, 2, 28)
    versions = []
    for minor in range(11, -1, -1):
        for patch in range(4, -1, -1):
            versions.append("3.%d.%d" % (minor, patch))
    for version in versions:
        if len(lines) >= 895:
            break
        lines += ["## [%s] - %s" % (version, date.isoformat()), ""]
        date -= datetime.timedelta(days=rng.randint(6, 19))
        for title, pool in CL_SECTIONS:
            if title == "Removed" and rng.random() < 0.6:
                continue
            lines += ["### %s" % title, ""]
            for template in rng.sample(pool, min(len(pool), rng.randint(2, 4))):
                lines.append("- " + template % rng.choice(CL_AREAS) + " Reported by the %s team (#%d)." % (rng.choice(["platform", "support", "growth", "finance", "mobile"]), rng.randint(1000, 9999)))
            lines.append("")
    write(out, "CHANGELOG.md", "\n".join(lines))


# --- 9. readme-typo -----------------------------------------------------------------------

def gen_readme(out, rng):
    lines = ["# Parcel Notes", "", "A small command line tool that keeps delivery notes next to your code.", "",
             "## Install", "", "    pip install parcel-notes", "", "## Usage", "",
             "Run `parcel add \"note text\"` to store a note. Notes are plain text files in `.parcel/`.", "",
             "## How it works", "",
             "Each note is stored with a timestamp. When a teammate pushes a note you will recieve it on the next sync.",
             "", "## Commands", ""]
    commands = ["add", "list", "show", "edit", "remove", "search", "export", "import", "sync", "status", "tag", "untag",
                "archive", "restore", "stats", "pin", "unpin", "diff", "merge", "split", "move", "copy", "rename", "link", "unlink", "watch", "unwatch", "digest", "remind", "snooze", "lock", "unlock", "clean", "verify", "config", "version", "help"]
    fixed_tail = ["", "## Configuration", "", "Settings live in `.parcel/config.json`.", "", "## License", "", "MIT"]
    need = 60 - len(lines) - len(fixed_tail)
    for cmd in commands[:need]:
        lines.append("- `parcel %s` %s" % (cmd, rng.choice(["works on the current folder.", "accepts --quiet.", "prints one line per note.", "returns 0 on success."])))
    lines += fixed_tail
    if len(lines) != 60:
        raise SystemExit("readme has %d lines" % len(lines))
    write(out, "README.md", "\n".join(lines))


# --- 10. timeparse-coverage -----------------------------------------------------------------

TIMEPARSE = '''"""Parse human duration strings such as "1h30m", "90s" or "1.5d" into seconds."""
import re

UNIT_SECONDS = {
    "s": 1,
    "m": 60,
    "h": 3600,
    "d": 86400,
    "w": 604800,
}

UNIT_ALIASES = {
%(aliases)s
}

_TOKEN = re.compile(r"(\\d+(?:\\.\\d+)?)\\s*([a-zA-Z]+)")


class DurationError(ValueError):
    """Raised when a duration string cannot be parsed."""


def _canonical_unit(word):
    unit = UNIT_ALIASES.get(word.lower())
    if unit is None:
        raise DurationError("unknown unit %%r" %% word)
    return unit


def parse_duration(text):
    """Return the number of seconds described by text.

    Accepts one or more number-unit pairs: "90s", "1h30m", "2 days 4 hours".
    A bare number is read as seconds. Fractions are allowed: "1.5h" is 5400.
    A leading minus sign is rejected; durations are never negative.
    """
    if text is None:
        raise DurationError("duration is required")
    cleaned = str(text).strip()
    if not cleaned:
        raise DurationError("duration is empty")
    if cleaned.startswith("-"):
        raise DurationError("duration cannot be negative")
    if re.fullmatch(r"\\d+(?:\\.\\d+)?", cleaned):
        return float(cleaned)
    position = 0
    total = 0.0
    for match in _TOKEN.finditer(cleaned):
        gap = cleaned[position:match.start()].strip(" ,")
        if gap:
            raise DurationError("unexpected text %%r" %% gap)
        number, word = match.groups()
        total += float(number) * UNIT_SECONDS[_canonical_unit(word)]
        position = match.end()
    if position == 0:
        raise DurationError("no duration found in %%r" %% cleaned)
    if cleaned[position:].strip(" ,"):
        raise DurationError("unexpected text %%r" %% cleaned[position:])
    return total


def format_duration(seconds):
    """Render seconds as the shortest "1h30m"-style string."""
    if seconds < 0:
        raise DurationError("duration cannot be negative")
    remaining = int(seconds)
    parts = []
    for unit in ("w", "d", "h", "m", "s"):
        size = UNIT_SECONDS[unit]
        count, remaining = divmod(remaining, size)
        if count:
            parts.append("%%d%%s" %% (count, unit))
    return "".join(parts) or "0s"


def clamp_duration(text, low, high):
    """Parse text and clamp the result to the inclusive range low..high seconds."""
    if low > high:
        raise DurationError("low bound exceeds high bound")
    value = parse_duration(text)
    if value < low:
        return float(low)
    if value > high:
        return float(high)
    return value


def add_durations(*texts):
    """Return the sum of several duration strings, in seconds."""
    total = 0.0
    for text in texts:
        total += parse_duration(text)
    return total


def scale_duration(text, factor):
    """Multiply a duration string by a non-negative factor."""
    if factor < 0:
        raise DurationError("factor cannot be negative")
    return parse_duration(text) * factor


def split_duration(seconds):
    """Break seconds into a dict of weeks, days, hours, minutes and seconds."""
    if seconds < 0:
        raise DurationError("duration cannot be negative")
    remaining = int(seconds)
    result = {}
    for unit in ("w", "d", "h", "m", "s"):
        size = UNIT_SECONDS[unit]
        result[unit], remaining = divmod(remaining, size)
    return result


def is_duration(text):
    """Return True when text parses as a duration."""
    try:
        parse_duration(text)
    except DurationError:
        return False
    return True


def longest_unit(seconds):
    """Return the largest unit that fits at least once into seconds."""
    if seconds < 0:
        raise DurationError("duration cannot be negative")
    for unit in ("w", "d", "h", "m"):
        if seconds >= UNIT_SECONDS[unit]:
            return unit
    return "s"


def round_duration(seconds, unit="m"):
    """Round seconds to the nearest whole unit and return the result in seconds."""
    if unit not in UNIT_SECONDS:
        raise DurationError("unknown unit %%r" %% unit)
    size = UNIT_SECONDS[unit]
    return float(round(seconds / size) * size)


def describe_duration(text):
    """Return a sentence such as "1 hour and 30 minutes" for a duration string."""
    names = {"w": "week", "d": "day", "h": "hour", "m": "minute", "s": "second"}
    parts = split_duration(parse_duration(text))
    phrases = []
    for unit in ("w", "d", "h", "m", "s"):
        count = parts[unit]
        if count:
            phrases.append("%%d %%s%%s" %% (count, names[unit], "" if count == 1 else "s"))
    if not phrases:
        return "0 seconds"
    if len(phrases) == 1:
        return phrases[0]
    return ", ".join(phrases[:-1]) + " and " + phrases[-1]


def parse_many(texts):
    """Parse several duration strings and return the list of seconds."""
    return [parse_duration(text) for text in texts]


def longest_of(texts):
    """Return the longest duration among texts, in seconds."""
    values = parse_many(texts)
    if not values:
        raise DurationError("no durations given")
    return max(values)


def shortest_of(texts):
    """Return the shortest duration among texts, in seconds."""
    values = parse_many(texts)
    if not values:
        raise DurationError("no durations given")
    return min(values)


def average_of(texts):
    """Return the mean of several durations, in seconds."""
    values = parse_many(texts)
    if not values:
        raise DurationError("no durations given")
    return sum(values) / len(values)
'''

ALIASES = [("sec", "s"), ("secs", "s"), ("second", "s"), ("seconds", "s"), ("min", "m"), ("mins", "m"),
           ("minute", "m"), ("minutes", "m"), ("hr", "h"), ("hrs", "h"), ("hour", "h"), ("hours", "h"),
           ("day", "d"), ("days", "d"), ("wk", "w"), ("wks", "w"), ("week", "w"), ("weeks", "w"),
           ("s", "s"), ("m", "m"), ("h", "h"), ("d", "d"), ("w", "w")]


def gen_timeparse(out, rng):
    alias_lines = "\n".join('    "%s": "%s",' % (a, b) for a, b in ALIASES)
    text = TIMEPARSE % {"aliases": alias_lines}
    # %% in the template is a literal percent in the output.
    write(out, "timeparse.py", text)


# --- 11. ratelimit-clock-skew -----------------------------------------------------------------

RATELIMIT_HEAD = '''"""Token-bucket rate limiting.

Each bucket refills at a steady rate up to a burst ceiling. Elapsed time is
measured with the monotonic clock only: wall-clock time can jump backwards or
forwards (NTP steps, VM resume, manual changes), and a bucket that trusted it
would either hand out a flood of tokens or freeze. When a reading ever moves
backwards anyway (a buggy injected clock, a suspended process on an odd
platform) the bucket treats the interval as zero and re-anchors, so the next
refill is measured from the new reading and never from a stale one.
"""
import threading
import time


class RateLimited(Exception):
    """Raised by acquire() when a token is not available."""

    def __init__(self, retry_after):
        super().__init__("rate limited, retry in %.3fs" % retry_after)
        self.retry_after = retry_after


class TokenBucket:
    """A thread-safe token bucket driven by a monotonic clock."""

    def __init__(self, rate, burst, clock=time.monotonic):
        if rate <= 0:
            raise ValueError("rate must be positive")
        if burst < 1:
            raise ValueError("burst must be at least one token")
        self._rate = float(rate)
        self._burst = float(burst)
        self._clock = clock
        self._tokens = float(burst)
        self._last = clock()
        self._lock = threading.Lock()
        self.skew_events = 0

    def _refill(self):
        """Add the tokens earned since the last reading. Caller holds the lock."""
        now = self._clock()
        elapsed = now - self._last
        if elapsed < 0:
            # The clock went backwards. Earn nothing for this interval and
            # re-anchor on the new reading so the skew cannot be replayed.
            self.skew_events += 1
            elapsed = 0.0
        self._last = now
        self._tokens = min(self._burst, self._tokens + elapsed * self._rate)

    def try_acquire(self, count=1):
        """Take count tokens if available; return True on success."""
        if count > self._burst:
            raise ValueError("cannot acquire more than the burst size")
        with self._lock:
            self._refill()
            if self._tokens >= count:
                self._tokens -= count
                return True
            return False

    def acquire(self, count=1):
        """Take count tokens or raise RateLimited with the wait needed."""
        if count > self._burst:
            raise ValueError("cannot acquire more than the burst size")
        with self._lock:
            self._refill()
            if self._tokens >= count:
                self._tokens -= count
                return
            missing = count - self._tokens
            raise RateLimited(missing / self._rate)

    def available(self):
        with self._lock:
            self._refill()
            return self._tokens


class KeyedLimiter:
    """One bucket per key, created on first use."""

    def __init__(self, rate, burst, clock=time.monotonic):
        self._rate = rate
        self._burst = burst
        self._clock = clock
        self._buckets = {}
        self._lock = threading.Lock()

    def bucket(self, key):
        with self._lock:
            existing = self._buckets.get(key)
            if existing is None:
                existing = TokenBucket(self._rate, self._burst, self._clock)
                self._buckets[key] = existing
            return existing

    def try_acquire(self, key, count=1):
        return self.bucket(key).try_acquire(count)

    def skew_total(self):
        with self._lock:
            return sum(b.skew_events for b in self._buckets.values())


class Preset:
    """Named limiter settings used by the service configuration."""

    def __init__(self, name, rate, burst, scope, note):
        self.name = name
        self.rate = rate
        self.burst = burst
        self.scope = scope
        self.note = note

    def make(self, clock=time.monotonic):
        return KeyedLimiter(self.rate, self.burst, clock)


PRESETS = {}

'''

RL_TOPICS = ["login", "search", "export", "upload", "webhook", "report", "invite", "reset", "sync", "profile", "billing",
             "comment", "share", "import", "preview", "ticket", "digest", "media", "audit", "token"]
RL_SCOPES = ["user", "ip", "tenant", "device"]
RL_NOTES = ["absorbs short bursts from interactive clients without letting a single noisy caller drain the shared quota for the rest",
            "keeps background jobs from starving foreground traffic by giving the batch workers a smaller and slower bucket than users",
            "protects the downstream provider quota, which is billed per call and rejects anything above its own published ceiling",
            "limits repeated attempts from one source so that credential guessing and scripted retries stay below an alerting threshold",
            "smooths bulk operations over a minute so the nightly import does not collide with the morning traffic peak on the API"]


def gen_ratelimit(out, rng):
    lines = RATELIMIT_HEAD.split("\n")[:-1]
    for i in range(90):
        name = "%s_%s_%02d" % (rng.choice(RL_TOPICS), rng.choice(RL_SCOPES), i)
        lines += ['PRESETS["%s"] = Preset(' % name,
                  '    name="%s", rate=%.1f, burst=%d, scope="%s",' % (name, rng.choice([0.5, 1.0, 2.0, 5.0, 10.0, 20.0]), rng.choice([5, 10, 20, 50, 100]), rng.choice(RL_SCOPES)),
                  '    note="%s",' % rng.choice(RL_NOTES), ")"]
    lines += ["", "", "def preset(name):", '    """Return a named preset or raise KeyError."""', "    return PRESETS[name]"]
    text = "\n".join(lines) + "\n"
    if len(text.encode("utf-8")) >= 30000:
        raise SystemExit("ratelimit.py is %d bytes" % len(text))
    write(out, "ratelimit.py", text)


# case name -> (seed, generator); one table so a case cannot have one without the other
CASES = {
    "billing-client-zero-total": (11, gen_billing),
    "nightly-pipeline-failure": (12, gen_log),
    "catalog-currency-field": (13, gen_catalog),
    "orders-extract-tax": (14, gen_orders),
    "pipeline-checks-intermittent": (15, gen_checks),
    "settings-loader-port": (16, gen_settings),
    "load-record-callers": (17, gen_svc),
    "changelog-release-notes": (18, gen_changelog),
    "readme-typo": (19, gen_readme),
    "timeparse-coverage": (20, gen_timeparse),
    "ratelimit-clock-skew": (21, gen_ratelimit),
}


def main(argv):
    parser = argparse.ArgumentParser(description="Generate one fixture workspace.")
    parser.add_argument("case", choices=sorted(CASES))
    parser.add_argument("--out", required=True, help="directory to write the fixture into")
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    seed, generate = CASES[args.case]
    generate(args.out, random.Random(seed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
