import assert from 'node:assert/strict'
import { EventEmitter, once } from 'node:events'
import { mkdtempSync, readFileSync, realpathSync, rmSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createInterface } from 'node:readline'
import { PassThrough } from 'node:stream'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { observeRunWait } from './observe-run-wait.mjs'

test('persists ordered progress before releasing the sole wait response', { timeout: 5_000 }, async t => {
  const directory = realpathSync(mkdtempSync(join(tmpdir(), 'wardpulse-observe-')))
  const output = join(directory, 'receipts')
  const server = new EventEmitter()
  server.stdin = new PassThrough()
  server.stdout = new PassThrough()
  server.stderr = new PassThrough()
  server.unref = () => {}
  const requests = []
  const dispatched = []
  const input = createInterface({ input: server.stdin })
  const controller = new AbortController()
  let observation
  let launchArguments
  let waitArrived
  let progressArrived
  const waiting = new Promise(resolve => { waitArrived = resolve })
  const progressed = new Promise(resolve => { progressArrived = resolve })
  const write = message => server.stdout.write(`${JSON.stringify(message)}\n`)
  const initializeResponse = {
    jsonrpc: '2.0', id: 1,
    result: { protocolVersion: '2025-11-25', capabilities: { tools: {} }, serverInfo: { name: 'controlled-server', version: '1' } },
  }
  input.on('line', line => {
    const request = JSON.parse(line)
    requests.push(request)
    if (request.method === 'initialize') write(initializeResponse)
    if (request.method === 'tools/call') waitArrived(request)
  })
  server.stdin.once('finish', () => {
    const drained = Promise.all([once(server.stdout, 'end'), once(server.stderr, 'end')])
    server.stdout.end()
    server.stderr.end()
    void drained.then(() => {
      server.emit('exit', 0, null)
      server.emit('close', 0, null)
    })
  })
  const abort = () => controller.abort()
  t.signal.addEventListener('abort', abort, { once: true })
  t.after(async () => {
    controller.abort()
    server.stdin.end()
    try {
      await observation
    } finally {
      t.signal.removeEventListener('abort', abort)
      input.close()
      server.stdin.destroy()
      server.stdout.destroy()
      server.stderr.destroy()
      rmSync(directory, { recursive: true, force: true })
    }
  })
  const options = {
    node: process.execPath, runnerEntry: fileURLToPath(import.meta.url), project: directory,
    runId: '11111111-1111-4111-8111-111111111111', cursor: 3, waitMs: 900_000,
    output, qualifiedBinding: true, soleObserver: true,
  }
  observation = observeRunWait(options, {
    signal: controller.signal,
    launch: (...args) => { launchArguments = args; return server },
    onProgress: message => {
      dispatched.push(message)
      if (dispatched.length === 2) progressArrived()
    },
  })
  let settled = false
  const endedEarly = observation.then(() => { settled = true; throw new Error('Wait settled before the controlled response') })
  const wait = await Promise.race([waiting, endedEarly])
  const token = wait.params._meta.progressToken
  assert.equal(typeof token, 'string')
  assert.ok(token.length > 0)
  const progress = [7, 9].map(revision => ({
    jsonrpc: '2.0', method: 'notifications/progress',
    params: { progressToken: token, progress: revision, message: `Public revision ${revision}` },
  }))
  write({ ...progress[0], params: { ...progress[0].params, progressToken: 'unrelated-token' } })
  progress.forEach(write)
  await Promise.race([progressed, endedEarly])
  assert.equal(settled, false)
  assert.equal(server.stdin.writableEnded, false)
  assert.deepEqual(dispatched, progress)
  assert.deepEqual(readFileSync(join(output, 'progress.jsonl'), 'utf8').trim().split('\n').map(JSON.parse), progress)
  const finalResponse = {
    jsonrpc: '2.0', id: wait.id,
    result: { content: [{ type: 'text', text: 'Controlled public result' }], structuredContent: { runId: options.runId, activityCursor: 12, timedOut: true } },
  }
  write(finalResponse)
  const result = await observation
  assert.deepEqual(launchArguments, [options.node, [options.runnerEntry, 'mcp'], { cwd: directory, stdio: ['pipe', 'pipe', 'pipe'] }])
  assert.deepEqual(requests, [
    { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'wardpulse-run-wait-observer', version: '1.0.0' } } },
    { jsonrpc: '2.0', method: 'notifications/initialized' },
    { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'run_wait', arguments: { runId: options.runId, cursor: 3, timeoutMs: 900_000, progress: true }, _meta: { progressToken: token } } },
  ])
  assert.deepEqual(result.initializeResponse, initializeResponse)
  assert.deepEqual(result.finalResponse, finalResponse)
  assert.equal(result.activityCursor, 12)
  assert.equal(result.waitOutcome, 'timedOut')
  assert.deepEqual(result.failures, [])
  assert.deepEqual(result.cleanup, { limitMs: 5_000, exit: { code: 0, signal: null }, streamsClosed: true, limitReached: false })
  assert.deepEqual(JSON.parse(readFileSync(join(output, 'outcome.json'), 'utf8')), result)
  assert.equal(statSync(output).mode & 0o777, 0o700)
  for (const file of ['progress.jsonl', 'stderr.log', 'outcome.json']) {
    assert.equal(statSync(join(output, file)).mode & 0o777, 0o600)
  }
})
