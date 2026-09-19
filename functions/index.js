const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');

admin.initializeApp();
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 });

const db = admin.firestore();
const sizes = new Set(['S', 'M', 'L', 'XL']);

function requireString(value, field) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', `${field} is required.`);
  }
  return value.trim();
}

function requirePositiveInteger(value, field) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new HttpsError('invalid-argument', `${field} must be a positive integer.`);
  }
  return value;
}

function requireFiniteNumber(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw new HttpsError('invalid-argument', `${field} must be a valid number.`);
  }
  return value;
}

async function processOrder(input, callerUid) {
  const orderId = requireString(input.orderId, 'orderId');
  const customer = input.customer;
  const shippingAddress = input.shippingAddress;
  const rawItems = input.items;

  if (!customer || typeof customer !== 'object') {
    throw new HttpsError('invalid-argument', 'Customer details are required.');
  }
  if (!shippingAddress || typeof shippingAddress !== 'object') {
    throw new HttpsError('invalid-argument', 'Shipping address is required.');
  }
  if (!Array.isArray(rawItems) || rawItems.length === 0 || rawItems.length > 50) {
    throw new HttpsError('invalid-argument', 'The order must contain items.');
  }

  const name = requireString(customer.name, 'customer.name');
  const email = requireString(customer.email, 'customer.email');
  const phone = requireString(customer.phone, 'customer.phone');
  const address = requireString(shippingAddress.address, 'shippingAddress.address');
  const city = requireString(shippingAddress.city, 'shippingAddress.city');
  const postalCode = requireString(shippingAddress.postalCode, 'shippingAddress.postalCode');

  const items = rawItems.map((rawItem, index) => {
    if (!rawItem || typeof rawItem !== 'object') {
      throw new HttpsError('invalid-argument', `items[${index}] is invalid.`);
    }
    const productId = requireString(rawItem.productId, `items[${index}].productId`);
    const size = requireString(rawItem.size, `items[${index}].size`);
    if (!sizes.has(size)) {
      throw new HttpsError('invalid-argument', `items[${index}].size is invalid.`);
    }
    return {
      productId,
      size,
      quantity: requirePositiveInteger(rawItem.quantity, `items[${index}].quantity`),
    };
  });

  const orderReference = db.collection('orders').doc(orderId);
  const result = await db.runTransaction(async (transaction) => {
    const existingOrder = await transaction.get(orderReference);
    if (existingOrder.exists) {
      const existingData = existingOrder.data();
      if (existingData.customerId !== callerUid) {
        throw new HttpsError('already-exists', 'This order reference is already in use.');
      }
      return {
        orderNumber: existingData.orderNumber,
        alreadyCreated: true,
      };
    }

    const productIds = [...new Set(items.map((item) => item.productId))];
    const productReferences = productIds.map((productId) => db.collection('products').doc(productId));
    const productSnapshots = await transaction.getAll(...productReferences);
    const quantitiesByProductAndSize = new Map();
    const orderItems = [];
    let totalPrice = 0;

    items.forEach((item, index) => {
      const snapshot = productSnapshots[index];
      const data = snapshot.data();
      if (!snapshot.exists || !data || data.published !== true) {
        throw new HttpsError('failed-precondition', 'One of the products is no longer available.');
      }

      const stockBySize = data.stockBySize;
      const stock = stockBySize && typeof stockBySize[item.size] === 'number'
        ? stockBySize[item.size]
        : 0;
      const quantityKey = `${item.productId}:${item.size}`;
      const requestedForSize =
        (quantitiesByProductAndSize.get(quantityKey) || 0) + item.quantity;
      if (requestedForSize > stock) {
        throw new HttpsError(
          'failed-precondition',
          `${data.name || 'A product'} does not have enough stock in size ${item.size}.`,
        );
      }
      quantitiesByProductAndSize.set(quantityKey, requestedForSize);

      const unitPrice = requireFiniteNumber(data.price, `products/${item.productId}.price`);
      const lineTotal = unitPrice * item.quantity;
      totalPrice += lineTotal;
      orderItems.push({
        productId: item.productId,
        name: requireString(data.name, `products/${item.productId}.name`),
        size: item.size,
        quantity: item.quantity,
        unitPrice,
        totalPrice: lineTotal,
      });
    });

    const now = new Date();
    const datePart = now.toISOString().slice(0, 10).replaceAll('-', '');
    const orderNumber = `RINA-${datePart}-${orderId.slice(0, 6).toUpperCase()}`;

    for (const productId of productIds) {
      const itemIndexes = items
        .map((item, index) => item.productId === productId ? index : -1)
        .filter((index) => index >= 0);
      const productIndex = productIds.indexOf(productId);
      const productData = productSnapshots[productIndex].data();
      const nextStock = { ...productData.stockBySize };
      for (const index of itemIndexes) {
        const item = items[index];
        nextStock[item.size] -= item.quantity;
      }
      transaction.update(productReferences[productIndex], {
        stockBySize: nextStock,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    transaction.set(orderReference, {
      orderNumber,
      customerId: callerUid,
      customer: { name, email, phone },
      shippingAddress: { address, city, postalCode },
      items: orderItems,
      totalPrice,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.set(db.collection('mail').doc(), {
      to: email,
      orderId,
      customerId: callerUid,
      type: 'order_created',
      message: {
        subject: `Order ${orderNumber} received`,
        text: `Thank you for your order. Your order number is ${orderNumber}. We will email you when its status changes.`,
        html: `<h2>Thank you for your order</h2><p>Your order number is <strong>${orderNumber}</strong>.</p><p>We will email you when its status changes.</p>`,
      },
    });

    return { orderNumber, alreadyCreated: false };
  });

  return result;
}

async function verifyToken(token) {
  if (typeof token !== 'string' || token.length === 0) {
    throw new HttpsError('unauthenticated', 'A Firebase customer token is required.');
  }
  try {
    return (await admin.auth().verifyIdToken(token)).uid;
  } catch (error) {
    console.error('Customer token verification failed.', error);
    throw new HttpsError('unauthenticated', 'The Firebase customer token was rejected.');
  }
}

exports.placeOrder = onCall(async (request) => {
  const input = request.data || {};
  const callerUid = request.auth?.uid || await verifyToken(input.idToken);
  return processOrder(input, callerUid);
});

exports.placeOrderHttp = onRequest(async (request, response) => {
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  response.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (request.method === 'OPTIONS') {
    response.status(204).send('');
    return;
  }
  if (request.method !== 'POST') {
    response.status(405).json({ error: 'POST is required.' });
    return;
  }
  try {
    const authorization = request.get('Authorization') || '';
    const token = authorization.startsWith('Bearer ')
      ? authorization.substring('Bearer '.length)
      : '';
    const callerUid = await verifyToken(token);
    const result = await processOrder(request.body || {}, callerUid);
    response.status(200).json(result);
  } catch (error) {
    const code = error instanceof HttpsError ? error.code : 'internal';
    const message = error instanceof HttpsError
      ? error.message
      : error instanceof Error
        ? error.message
        : 'Unable to place the order.';
    console.error('HTTP order placement failed.', error);
    response.status(code === 'unauthenticated' ? 401 : 400).json({ code, message });
  }
});
