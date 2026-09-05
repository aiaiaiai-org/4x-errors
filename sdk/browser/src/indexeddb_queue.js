// © 2026 aiaiaiai · aiaiaiai.org
// SPDX-License-Identifier: Apache-2.0

const DEFAULT_DATABASE_NAME = '4x-errors';
const DEFAULT_MAX_ENTRIES = 1_000;
const DATABASE_VERSION = 1;
const STORE_NAME = 'events';

export function createIndexedDbQueue(options = {}) {
  const factory = options.indexedDB ?? globalThis.indexedDB;
  if (!factory || typeof factory.open !== 'function') return createUnavailableQueue();

  const databaseName = nonEmptyString(options.databaseName)
    ? options.databaseName
    : DEFAULT_DATABASE_NAME;
  const maxEntries = positiveInteger(options.maxEntries)
    ? options.maxEntries
    : DEFAULT_MAX_ENTRIES;

  return new IndexedDbEventQueue(factory, databaseName, maxEntries);
}

class IndexedDbEventQueue {
  available = true;

  #factory;
  #databaseName;
  #maxEntries;
  #databasePromise;

  constructor(factory, databaseName, maxEntries) {
    this.#factory = factory;
    this.#databaseName = databaseName;
    this.#maxEntries = maxEntries;
    this.#databasePromise = null;
  }

  async enqueue(event) {
    const database = await this.#database();
    const transaction = database.transaction(STORE_NAME, 'readwrite');
    const done = transactionDone(transaction);
    const store = transaction.objectStore(STORE_NAME);
    store.add({ event_id: event.event_id, event });
    await trimOldest(store, this.#maxEntries);
    await done;
  }

  async peek(limit = 50) {
    const database = await this.#database();
    const transaction = database.transaction(STORE_NAME, 'readonly');
    const done = transactionDone(transaction);
    const store = transaction.objectStore(STORE_NAME);
    const events = await readOldest(store, positiveInteger(limit) ? limit : 50);
    await done;
    return events;
  }

  async remove(eventIds) {
    const ids = new Set(Array.isArray(eventIds) ? eventIds : []);
    if (ids.size === 0) return;

    const database = await this.#database();
    const transaction = database.transaction(STORE_NAME, 'readwrite');
    const done = transactionDone(transaction);
    const store = transaction.objectStore(STORE_NAME);
    await deleteByEventIds(store, ids);
    await done;
  }

  async size() {
    const database = await this.#database();
    const transaction = database.transaction(STORE_NAME, 'readonly');
    const done = transactionDone(transaction);
    const count = await requestResult(transaction.objectStore(STORE_NAME).count());
    await done;
    return count;
  }

  async #database() {
    this.#databasePromise ??= openDatabase(this.#factory, this.#databaseName);
    return this.#databasePromise;
  }
}

function createUnavailableQueue() {
  return {
    available: false,
    enqueue: async () => undefined,
    peek: async () => [],
    remove: async () => undefined,
    size: async () => 0
  };
}

function openDatabase(factory, databaseName) {
  return new Promise((resolve, reject) => {
    const request = factory.open(databaseName, DATABASE_VERSION);

    request.onupgradeneeded = () => {
      const database = request.result;
      if (database.objectStoreNames.contains(STORE_NAME)) return;

      const store = database.createObjectStore(STORE_NAME, {
        keyPath: 'id',
        autoIncrement: true
      });
      store.createIndex('event_id', 'event_id', { unique: true });
    };
    request.onsuccess = () => {
      const database = request.result;
      database.onversionchange = () => database.close();
      resolve(database);
    };
    request.onerror = () => reject(request.error ?? new Error('IndexedDB open failed'));
    request.onblocked = () => reject(new Error('IndexedDB open blocked'));
  });
}

async function trimOldest(store, maxEntries) {
  const count = await requestResult(store.count());
  let remaining = Math.max(0, count - maxEntries);
  if (remaining === 0) return;

  await cursorWalk(store.openCursor(), (cursor) => {
    if (remaining === 0) return false;
    cursor.delete();
    remaining -= 1;
    return remaining > 0;
  });
}

function readOldest(store, limit) {
  const events = [];
  return cursorWalk(store.openCursor(), (cursor) => {
    events.push(cursor.value.event);
    return events.length < limit;
  }).then(() => events);
}

function deleteByEventIds(store, eventIds) {
  return cursorWalk(store.openCursor(), (cursor) => {
    if (eventIds.has(cursor.value.event_id)) cursor.delete();
    return true;
  });
}

function cursorWalk(request, visit) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor || visit(cursor) === false) {
        resolve();
        return;
      }
      cursor.continue();
    };
    request.onerror = () => reject(request.error ?? new Error('IndexedDB cursor failed'));
  });
}

function requestResult(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('IndexedDB request failed'));
  });
}

function transactionDone(transaction) {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onabort = () => reject(transaction.error ?? new Error('IndexedDB transaction aborted'));
    transaction.onerror = () => reject(transaction.error ?? new Error('IndexedDB transaction failed'));
  });
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

function positiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}
