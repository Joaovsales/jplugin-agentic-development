// An order whose lifecycle is spread across handlers: the implicit machine.
let order = { status: 'pending', isPaid: false, isShipping: false };

export function pay() {
  if (order.status === 'pending') {
    order.isPaid = true;
    setStatus('paid');
  }
}

export function ship() {
  // No guard on isPaid: a pending order can ship.
  order.isShipping = true;
  setStatus('shipped');
}

export function cancel() {
  setStatus('cancelled');
}

function setStatus(next) {
  order.status = next;
}

export function render() {
  switch (order.status) {
    case 'pending': return 'Waiting for payment';
    case 'paid': return 'Paid';
    case 'shipped': return 'On its way';
    default: return 'Cancelled';
  }
}
