# Expected findings

Four diffs sit beside this file. Three carry one real defect each. One carries none.

Line numbers come in two forms. "Diff line" counts from the `diff --git` header at line 1. "New-file line" counts inside the added file, which starts at line 1.

## invite-redeem.diff

- Defect class: race condition (check then write, not atomic).
- File: `app/invites.py`.
- Check line (diff line 20, new-file line 15): `+    if invite.redeemed_at is not None:`
- Write line (diff line 25, new-file line 20): `+    invite.redeemed_at = datetime.now(timezone.utc)`
- Trigger: two requests redeem the same code at the same moment. Both read `redeemed_at` as `None`. Both pass the check. Both write the row and both add a `Membership`.
- Wrong result: a single-use invite grants membership twice. The second `redeemed_by` overwrites the first.
- Expected severity: MUST-FIX.
- Accepted fixes: a conditional update (`UPDATE ... WHERE redeemed_at IS NULL` and check the row count), a row lock (`SELECT ... FOR UPDATE`), or a unique constraint on the redemption.

## order-summary.diff

- Defect class: N+1 calls (one remote call per item in a loop).
- File: `app/reports.py`.
- Line (diff line 24, new-file line 19): `+        customer = crm_client.get_customer(order.customer_id)`
- Trigger: any account with many orders. The default limit is 50.
- Wrong result: one query for the orders, then up to 50 sequential HTTP calls to the CRM. Latency grows with the row count. A slow or rate-limited CRM stalls the whole report. Repeat customers are fetched again each time.
- Expected severity: SHOULD-FIX.
- Accepted fixes: fetch all customers in one batch call keyed by the distinct `customer_id` values, or join in the database.

## billing-cutoff.diff

- Defect class: time-zone off-by-one.
- File: `app/billing.py`.
- Line (diff line 23, new-file line 18): `+    today = now.date()`
- Related line (diff line 24, new-file line 19): `+    return today >= next_charge_date(sub)`
- Trigger: an account in `America/Los_Angeles` whose charge date is 2026-03-10. At 17:30 local on 2026-03-09 the UTC time is 00:30 on 2026-03-10. `now.date()` returns 2026-03-10, so `is_due` is true.
- Wrong result: the customer is charged a day early, on the evening of the 9th local time. `next_charge_date` is built in the account zone, but "today" is read in UTC. Accounts east of UTC are charged a day late in the opposite window.
- Expected severity: MUST-FIX.
- Accepted fixes: compute `today` as `now.astimezone(ZoneInfo(sub.account.timezone)).date()`.

## settings-merge.diff

- Result: no defect.
- Suspicious line (diff line 35, new-file line 30): `+        except KeyError:` followed by `return default`.
- Why it is correct: the docstring states that stored settings are sparse and a missing key yields `default`. The caller asked for a default, so returning it is the contract. The guard `if not isinstance(node, dict): return default` runs first, so the lookup never indexes a non-dict. `KeyError` is the only error left, and it is the expected one. Nothing is swallowed that should surface.
- Expected severity: none.

## Grading

- A reviewer gets recall credit for a diff when it names the defect's location and class. The location is the file plus the check/write or loop or date line given above. The class must match in meaning, not wording.
- Any finding on the settings-merge suspicious line counts as a false positive. So does any MUST-FIX or SHOULD-FIX on a line not listed in this key.
- NITPICK findings on other lines are neutral. They neither earn recall nor count as false positives.
- Report recall as caught defects out of three. Report false positives as a count across all four diffs.
