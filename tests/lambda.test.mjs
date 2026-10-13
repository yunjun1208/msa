import test from 'node:test';
import assert from 'node:assert/strict';
import { processRecords } from '../terraform/lambda/order_notifications/index.mjs';
const valid = { eventType: 'ORDER_CREATED', orderId: 7, memberId: 3, productId: 5, quantity: 2, recipientEmail: 'user@example.com' };
const makeRecord = (message, id = 'sq1') => ({ messageId: id, body: JSON.stringify({ Message: JSON.stringify(message) }) });
test('SQS -> SES accepted successful record', async () => {
  const received=[];
  const result=await processRecords({Records:[makeRecord(valid)]}, async x => received.push(x));
  assert.deepEqual(result, {batchItemFailures:[]});
  assert.deepEqual(received, [{orderId:7,recipient:'user@example.com',quantity:2}]);
});
test('poison record returns per-message failure (DLQ after 3 attempts)', async () => {
  const result=await processRecords({Records:[makeRecord({...valid, recipientEmail:'not-an-email'})]}, async () => {throw Error('should not call')});
  assert.deepEqual(result, {batchItemFailures:[{itemIdentifier:'sq1'}]});
});
test('SES failure returned for SQS retry', async () => {
  const result=await processRecords({Records:[makeRecord(valid)]}, async () => {throw Error('SES unavailable')});
  assert.deepEqual(result, {batchItemFailures:[{itemIdentifier:'sq1'}]});
});
