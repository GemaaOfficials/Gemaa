'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeAddress, isTrackerURL } = require('../src/browser-utils.cjs');

test('blank address opens the home page', () => {
  assert.equal(normalizeAddress(''), 'https://www.google.com/');
  assert.equal(normalizeAddress('   '), 'https://www.google.com/');
});

test('normalizes valid HTTP and HTTPS addresses', () => {
  assert.equal(normalizeAddress('https://example.com/path'), 'https://example.com/path');
  assert.equal(normalizeAddress('example.com/path'), 'https://example.com/path');
  assert.equal(normalizeAddress('localhost:5173'), 'http://localhost:5173');
});

test('treats ordinary text as a search query', () => {
  assert.equal(normalizeAddress('hello world'), 'https://www.google.com/search?q=hello%20world');
});

test('rejects executable and local-file URL schemes', () => {
  assert.equal(normalizeAddress('javascript:alert(1)'), null);
  assert.equal(normalizeAddress('file:///C:/Windows/system.ini'), null);
  assert.equal(normalizeAddress('data:text/html,hello'), null);
});

test('tracker blocker matches known ad hosts and subdomains', () => {
  assert.equal(isTrackerURL('https://doubleclick.net/abc.js'), true);
  assert.equal(isTrackerURL('https://stats.google-analytics.com/collect?v=1'), true);
  assert.equal(isTrackerURL('https://www.google-analytics.com/g/collect'), true);
});

test('tracker blocker does not block ordinary site URLs', () => {
  assert.equal(isTrackerURL('https://example.com/article'), false);
  assert.equal(isTrackerURL('https://developer.mozilla.org/en-US/'), false);
});
