#!/usr/bin/env python3
"""Generate fixed-seed commerce repositories; reference answers stay in this module.

The default arm is A. Graph arms require the already-installed pinned CLI;
--check-runtime verifies that prerequisite without generating or running an agent.
"""
import argparse
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys

CASES = {
    "invoice-rounding": {"seed": 101, "kind": "localization", "target_file": "billing/amounts.py", "target_symbol": "settle_amount", "prompt": "Checkout for two units at 1099 cents returns 2197 cents rather than 2198. Follow the checkout path and identify the function responsible, giving its file and name. Do not change files."},
    "dispatch-callers": {"seed": 102, "kind": "localization", "target_file": "gateway/queue.py", "target_symbol": "enqueue_dispatch", "prompt": "dispatch_parcel now requires a region argument. Find its callers and identify the one that still omits region, giving the file and containing function. Do not change files."},
    "currency-shape": {"seed": 103, "kind": "localization", "target_file": "catalog/mapper.ts", "target_symbol": "mapPrice", "prompt": "Money values now carry minor and unit fields. Trace the product-card consumers and identify the transformation still treating the value as a scalar; give its file and function. Do not change files."},
    "credit-flow": {"seed": 104, "kind": "localization", "target_file": "ledger/bridge.py", "target_symbol": "encode_credit", "prompt": "A credit of 1215 minor units arrives at the outbound message as 12. Trace the value through the modules and identify the function that first loses the cents, with its file. Do not change files."},
    "terms-failure": {"seed": 105, "kind": "localization", "target_file": "billing/policy.py", "target_symbol": "resolve_terms", "prompt": "The worker fails on the basic plan; its traceback is in logs/worker.log. Follow the stack to the root cause and name the responsible file and function. Do not change files."},
    "status-rename": {"seed": 106, "kind": "localization", "target_file": "notify/queue.py", "target_symbol": "publish_alert", "prompt": "The status-packing helper was renamed, and alert publishing no longer starts. Locate the stale use and give the file and function containing it. Do not change files."},
    "refund-balance": {"seed": 107, "kind": "localization", "target_file": "orders/receipt.py", "target_symbol": "apply_refund", "prompt": "Refunding 300 minor units from a balance of 1200 produces 1500. Trace the refund entry point and identify the arithmetic function responsible, giving its file and name. Do not change files."},
    "readme-copy": {"seed": 108, "kind": "control", "target_file": "README.md", "prompt": "Correct the spelling of reciept in README.md and tell me which file you changed."},
    "profile-port": {"seed": 109, "kind": "control", "target_file": "config/runtime.yaml", "prompt": "Change the local gateway port from 4210 to 4211 in config/runtime.yaml and tell me which file you changed."},
    "receipt-module": {"seed": 110, "kind": "control", "target_file": "reporting/receipt.py", "target_symbol": "format_receipt", "scaffold": True, "prompt": "Add reporting/receipt.py with format_receipt(reference, minor) returning reference followed by a colon and the integer minor amount. Tell me the file and function you added."},
}
DOMAINS = ("billing", "shipping", "ledger", "gateway", "catalog", "shared", "orders", "notify")
MODULES = ("amounts", "routes", "batch", "bridge", "cache", "limits", "mapper", "policy", "queue", "receipt")


def write(root, relative, text):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def append(root, relative, text):
    path = root / relative
    write(root, relative, path.read_text() + "\n" + text)


def generate(name, root):
    case = CASES[name]
    rng = random.Random(case["seed"])
    root.mkdir(parents=True, exist_ok=True)
    for domain in DOMAINS:
        write(root, domain + "/__init__.py", '"""Commerce services."""')
        for module in MODULES:
            py = ['"""Value transformations for commerce requests."""', ""]
            ts = ['// Value transformations for commerce requests.', ""]
            for index in range(26):
                scale = rng.randint(1, 9)
                py.extend([f"def adjust_{index:02d}(value, offset=0):", f"    scale = {scale}", "    shifted = value + offset", "    return shifted * scale", ""])
                ts.extend([f"export function adjust{index:02d}(value: number, offset = 0): number {{", f"  const scale = {scale};", "  const shifted = value + offset;", "  return shifted * scale;", "}", ""])
            write(root, f"{domain}/{module}.py", "\n".join(py))
            write(root, f"{domain}/{module}.ts", "\n".join(ts))

    append(root, "billing/amounts.py", "def settle_amount(units, price):\n    return units * price" + (" - 1" if name == "invoice-rounding" else ""))
    append(root, "billing/routes.py", "from billing.amounts import settle_amount\n\ndef price_invoice(units, price):\n    return settle_amount(units, price)")
    append(root, "shipping/routes.py", "def dispatch_parcel(parcel, region):\n    return {'parcel': parcel, 'region': region}")
    call = "dispatch_parcel(parcel)" if name == "dispatch-callers" else "dispatch_parcel(parcel, region)"
    append(root, "gateway/queue.py", "from shipping.routes import dispatch_parcel\n\ndef enqueue_dispatch(parcel, region):\n    return " + call)
    append(root, "shipping/queue.py", "from shipping.routes import dispatch_parcel\n\ndef enqueue_local(parcel):\n    return dispatch_parcel(parcel, 'local')")
    append(root, "shared/amounts.ts", "export type Money = { minor: number; unit: string };\nexport function money(minor: number, unit: string): Money { return { minor, unit }; }")
    price = "Number(amount) / 100" if name == "currency-shape" else "amount.minor / 100"
    append(root, "catalog/mapper.ts", 'import { Money } from "../shared/amounts";\nexport function mapPrice(amount: Money): number { return ' + price + "; }")
    append(root, "catalog/routes.ts", 'import { mapPrice } from "./mapper";\nimport { Money } from "../shared/amounts";\nexport function productCard(amount: Money): string { return String(mapPrice(amount)); }')
    append(root, "gateway/bridge.ts", 'import { money } from "../shared/amounts";\nimport { productCard } from "../catalog/routes";\nexport function catalogReply(minor: number): string { return productCard(money(minor, "USD")); }')
    credit = "amount // 100" if name == "credit-flow" else "amount"
    append(root, "ledger/bridge.py", "def encode_credit(amount):\n    return {'minor': " + credit + ", 'unit': 'USD'}")
    append(root, "notify/bridge.py", "import json\nfrom ledger.bridge import encode_credit\n\ndef credit_message(amount):\n    return json.dumps(encode_credit(amount))")
    terms = "table.get(plan)" if name == "terms-failure" else "table.get(plan, 30)"
    append(root, "billing/policy.py", "def resolve_terms(plan):\n    table = {'pro': 14}\n    return " + terms)
    append(root, "ledger/mapper.py", "from billing.policy import resolve_terms\n\ndef payment_days(plan):\n    return int(resolve_terms(plan))")
    append(root, "shared/mapper.py", "def pack_status(status):\n    return {'state': status}")
    symbol = "encode_status" if name == "status-rename" else "pack_status"
    append(root, "notify/queue.py", "from shared.mapper import " + symbol + "\n\ndef publish_alert(status):\n    return " + symbol + "(status)")
    refund = "balance + minor" if name == "refund-balance" else "balance - minor"
    append(root, "orders/receipt.py", "def apply_refund(balance, minor):\n    return " + refund)
    write(root, "app.py", "from billing.routes import price_invoice\nfrom gateway.queue import enqueue_dispatch\nfrom notify.bridge import credit_message\nfrom ledger.mapper import payment_days\nfrom orders.receipt import apply_refund\n\ndef checkout(units, price):\n    return price_invoice(units, price)\n\ndef refund(balance, minor):\n    return apply_refund(balance, minor)\n\ndef credit(amount):\n    return credit_message(amount)\n\ndef due_days(plan):\n    return payment_days(plan)")
    write(root, "README.md", "# Harbor commerce\n\nOperations enter through app.py.\nStore each " + ("reciept" if name == "readme-copy" else "receipt") + " with its reference.\n")
    write(root, "config/runtime.yaml", "gateway:\n  port: 4210\n  region: local")
    write(root, "logs/worker.log", 'Traceback (most recent call last):\n  File "app.py", line 17, in due_days\n    return payment_days(plan)\n  File "ledger/mapper.py", line 136, in payment_days\n    return int(resolve_terms(plan))\nTypeError: int() argument must be a string, a bytes-like object or a real number, not NoneType')


def graph_binary():
    pin = (Path(__file__).resolve().parents[2] / ".agents/graphify.pin").read_text().strip()
    binary = os.environ.get("CODE_GRAPH_REAL_GRAPHIFY") or shutil.which("graphify")
    if not binary:
        raise ValueError(f"graphify missing; a person must run install.sh for graphifyy=={pin}")
    result = subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=5)
    if result.returncode or result.stdout.strip().split()[-1:] != [pin]:
        raise ValueError(f"graphify version differs from pinned {pin}; a person must run install.sh")
    return str(Path(binary).resolve())


def prepare_arm(root, arm):
    if arm == "A":
        return
    binary = graph_binary()
    subprocess.run([binary, "update", "."], cwd=root, check=True, timeout=120, capture_output=True, text=True)
    if arm == "D":
        destination = os.environ.get("CODE_GRAPH_STUB_DIR")
        if not destination:
            raise ValueError("D requires CODE_GRAPH_STUB_DIR and that directory first on the runner PATH")
        destination = Path(destination)
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(Path(__file__).parent / "stubs/graphify", destination / "graphify")
        (destination / "graphify").chmod(0o755)
        if int(os.environ["CODE_GRAPH_SEED"]) % 4 == 3:
            write(root, "graphify-out/graph.json", "{broken")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", nargs="?", choices=CASES)
    parser.add_argument("--out", type=Path, default=Path("."))
    parser.add_argument("--arm", choices=("A", "B", "D"), default=os.environ.get("CODE_GRAPH_ARM", "A"))
    parser.add_argument("--check-runtime", action="store_true")
    args = parser.parse_args()
    if args.check_runtime:
        graph_binary()
        return
    if not args.case:
        parser.error("case is required unless --check-runtime is used")
    os.environ["CODE_GRAPH_SEED"] = str(CASES[args.case]["seed"])
    generate(args.case, args.out)
    prepare_arm(args.out.resolve(), args.arm)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"fixture preparation failed: {exc}", file=sys.stderr)
        sys.exit(2)
