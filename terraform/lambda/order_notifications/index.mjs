// AWS Lambda Node.js 22: SNS -> SQS envelope -> transactional email via SES v2.
// SES sender verification + account sending permissions are mandatory.
export async function processRecords(event, sendEmail) {
  const failures = [];
  for (const record of event.Records ?? []) {
    try {
      const envelope = JSON.parse(record.body);
      const message = typeof envelope.Message === 'string'
        ? JSON.parse(envelope.Message) : envelope;
      if (message.eventType !== 'ORDER_CREATED' ||
          !Number.isSafeInteger(message.orderId) ||
          !Number.isSafeInteger(message.memberId) ||
          !Number.isSafeInteger(message.quantity) || message.quantity <= 0 ||
          typeof message.recipientEmail !== 'string' ||
          !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(message.recipientEmail)) {
        throw new Error('Invalid ORDER_CREATED payload');
      }
      await sendEmail({
        orderId: message.orderId,
        recipient: message.recipientEmail,
        quantity: message.quantity
      });
      // No customer PII in logs.
      console.log(JSON.stringify({ status: 'EMAIL_SUBMITTED_TO_SES', orderId: message.orderId }));
    } catch (err) {
      console.error(JSON.stringify({ status: 'SEND_FAILED', messageId: record.messageId, reason: err.message }));
      failures.push({ itemIdentifier: record.messageId });
    }
  }
  return { batchItemFailures: failures };
}

export const handler = async (event) => {
  const from = process.env.SES_SENDER_EMAIL;
  if (!from) throw new Error('SES_SENDER_EMAIL must be set');
  // Lambda Node 22 includes AWS SDK for JavaScript v3. Lock dependency in a build
  // bundle for environments where the runtime-provided version changes.
  const { SESv2Client, SendEmailCommand } = await import('@aws-sdk/client-sesv2');
  const ses = new SESv2Client({ region: process.env.AWS_REGION });
  return processRecords(event, async ({ orderId, recipient, quantity }) => {
    await ses.send(new SendEmailCommand({
      FromEmailAddress: from,
      Destination: { ToAddresses: [recipient] },
      Content: {
        Simple: {
          Subject: { Data: `주문 접수 안내 #${orderId}`, Charset: 'UTF-8' },
          Body: { Text: { Data: `주문번호 ${orderId}번, 주문 수량 ${quantity}개가 접수되었습니다. 감사합니다.`, Charset: 'UTF-8' } }
        }
      }
    }));
  });
};
