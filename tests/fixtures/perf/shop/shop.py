"""A tiny shop backend with planted waste, for the /perf tests and the e2e audit.

Each planted line ends with a `planted:` comment naming the pattern the scanner
must report there; every other function is the clean twin and must stay silent.

    python3 shop.py orders [N]          # N+1: one customer query per order
    python3 shop.py orders-joined [N]   # the same rows with one join
    python3 shop.py dashboard           # two independent awaits, one after another
    python3 shop.py cart [N]            # one await per item, in turn
"""

import asyncio
import sqlite3
import sys


def connect(count):
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)")
    db.execute("CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, total REAL)")
    db.executemany("INSERT INTO customers VALUES (?, ?)", [(i, f"c{i}") for i in range(count)])
    db.executemany("INSERT INTO orders VALUES (?, ?, ?)", [(i, i, i * 1.5) for i in range(count)])
    return db


def list_orders(db):
    rows = db.execute("SELECT id, customer_id, total FROM orders").fetchall()
    out = []
    for order_id, customer_id, total in rows:
        name = db.execute("SELECT name FROM customers WHERE id = ?", (customer_id,)).fetchone()[0]  # planted: n-plus-one
        out.append((order_id, name, total))
    return out


def list_orders_joined(db):
    return db.execute(
        "SELECT o.id, c.name, o.total FROM orders o JOIN customers c ON c.id = o.customer_id"
    ).fetchall()


async def fetch_user(user_id):
    await asyncio.sleep(0.05)
    return {"id": user_id, "name": "ada"}


async def fetch_prefs(user_id):
    await asyncio.sleep(0.05)
    return {"user": user_id, "theme": "dark"}


async def fetch_item(item_id):
    await asyncio.sleep(0.01)
    return {"id": item_id}


async def dashboard(user_id):
    user = await fetch_user(user_id)  # planted: await-waterfall
    prefs = await fetch_prefs(user_id)
    return user, prefs


async def dashboard_dependent(user_id):
    user = await fetch_user(user_id)
    prefs = await fetch_prefs(user["id"])
    return user, prefs


async def cart(item_ids):
    items = []
    for item_id in item_ids:
        items.append(await fetch_item(item_id))  # planted: sequential-await
    return items


async def cart_gathered(item_ids):
    return await asyncio.gather(*(fetch_item(i) for i in item_ids))


def main(argv):
    command = argv[1] if len(argv) > 1 else "orders"
    count = int(argv[2]) if len(argv) > 2 else 2000
    if command == "orders":
        list_orders(connect(count))
    elif command == "orders-joined":
        list_orders_joined(connect(count))
    elif command == "dashboard":
        asyncio.run(dashboard(1))
    elif command == "cart":
        asyncio.run(cart(range(count if len(argv) > 2 else 10)))
    else:
        print(f"unknown command {command!r}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
