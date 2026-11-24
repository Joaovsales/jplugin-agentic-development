// A tiny client with planted waste, for the /perf tests. Each planted line
// ends with a `planted:` comment naming the pattern the scanner must report
// there; every other function is the clean twin and must stay silent.

export async function loadOrders(db, ids) {
  const orders = [];
  for (const id of ids) {
    const order = await db.query('SELECT * FROM orders WHERE id = $1', [id]); // planted: n-plus-one, sequential-await
    orders.push(order);
  }
  return orders;
}

export async function loadOrdersBatched(db, ids) {
  return db.query('SELECT * FROM orders WHERE id = ANY($1)', [ids]);
}

export async function loadDashboard(api) {
  const user = await api.getUser(); // planted: await-waterfall
  const prefs = await api.getPrefs();
  return { user, prefs };
}

export async function loadDependent(api) {
  const user = await api.getUser();
  const prefs = await api.getPrefs(user.id);
  return { user, prefs };
}

export async function loadAll(api, ids) {
  return Promise.all(ids.map(async (id) => await api.getItem(id)));
}

export function labels(items) {
  const names = [];
  for (const item of items) {
    names.push(`for (const x of y) { await db.query(x) } ${item.name}`);
  }
  return names;
}
