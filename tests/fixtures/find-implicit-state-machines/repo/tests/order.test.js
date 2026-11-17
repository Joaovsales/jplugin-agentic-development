import { pay, render } from '../src/order.js';
test('pay', () => { pay(); expect(render()).toBe('Paid'); });
