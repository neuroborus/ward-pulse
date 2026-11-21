import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'
import {
  accessSync, closeSync, constants, fstatSync, mkdirSync, openSync,
  realpathSync, statSync, writeFileSync,
} from 'node:fs'
import { isAbsolute, join, resolve } from 'node:path'
import { createInterface } from 'node:readline'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'

const PROTOCOL = '2025-11-25'
const CLEANUP_MS = 5_000
const STDERR_BYTES = 64 * 1024
const UNKNOWN = 'Unknown'
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value)
const cursor = value => Number.isSafeInteger(value) && value >= 0
class ProtocolFailure extends Error {}

function validate(options) {
  for (const key of ['node', 'runnerEntry', 'project', 'output']) {
    if (typeof options[key] !== 'string' || !isAbsolute(options[key])) {
      throw new Error(`${key} must be an explicitly qualified absolute path`)
    }
  }
  accessSync(options.node, constants.X_OK)
  if (!statSync(options.node).isFile() || !statSync(options.runnerEntry).isFile()) {
    throw new Error('node and runnerEntry must name qualified files')
  }
  if (realpathSync(options.project) !== options.project || !statSync(options.project).isDirectory()) {
    throw new Error('project must be its canonical directory path')
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(options.runId)) {
    throw new Error('runId must be a qualified UUID')
  }
  if (!cursor(options.cursor) || !cursor(options.waitMs) || options.waitMs > 86_400_000) {
    throw new Error('cursor must be a safe nonnegative integer; waitMs must be 0..86400000')
  }
  if (options.qualifiedBinding !== true || options.soleObserver !== true) {
    throw new Error('Caller must qualify the project/run binding and own the sole observation interval')
  }
}

// launch is an injectable child-process boundary for controlled local protocol verification.
export async function observeRunWait(options, { launch = spawn, onProgress = () => {}, signal } = {}) {
  validate(options)
  mkdirSync(options.output, { mode: 0o700 })
  const files = {}
  try {
    for (const name of ['progress.jsonl', 'stderr.log', 'outcome.json']) {
      files[name] = openSync(join(options.output, name), 'wx', 0o600)
    }
  } catch (error) {
    for (const fd of Object.values(files)) closeSync(fd)
    throw new Error(`Receipt creation failed (${error.code ?? 'Unknown'}); partial files are preserved`)
  }

  const receipt = {
    protocolVersion: PROTOCOL,
    callerAssertions: { qualifiedBinding: true, soleObserver: true },
    project: options.project,
    runId: options.runId,
    requestedCursor: options.cursor,
    waitMs: options.waitMs,
    progressToken: randomUUID(),
    progressCount: 0,
    initializeResponse: UNKNOWN,
    finalResponse: UNKNOWN,
    activityCursor: UNKNOWN,
    waitOutcome: UNKNOWN,
    failures: [],
    server: { node: options.node, entry: options.runnerEntry, pid: UNKNOWN },
    cleanup: { limitMs: CLEANUP_MS, exit: UNKNOWN, streamsClosed: false, limitReached: false },
    stderr: { file: 'stderr.log', limitBytes: STDERR_BYTES, observedBytes: 0, retainedBytes: 0, truncated: false },
  }
  let child
  let lines
  let pendingId = 1
  let finished = false
  let closing = false
  let sealed = false
  let stderrWritable = true
  let complete
  let closed
  const response = new Promise(resolveResponse => { complete = resolveResponse })
  const connectionClosed = new Promise(resolveClosed => { closed = resolveClosed })
  function finish() {
    finished = true
    complete()
  }
  function fail(kind, detail, code) {
    if (sealed) return
    receipt.failures.push({ kind, detail, ...(code === undefined ? {} : { code }) })
    finish()
  }
  function send(message) {
    try {
      child.stdin.write(`${JSON.stringify(message)}\n`, error => {
        if (error) fail('transport-failure', 'MCP stdin write failed', error.code)
      })
    } catch (error) {
      fail('transport-failure', 'MCP stdin write failed', error.code)
    }
  }
  function protocol(condition, detail) {
    if (!condition) throw new ProtocolFailure(detail)
  }
  function receive(line) {
    if (finished) return
    try {
      const message = JSON.parse(line)
      protocol(object(message) && message.jsonrpc === '2.0', 'Invalid JSON-RPC envelope')
      if (Object.hasOwn(message, 'method')) {
        protocol(typeof message.method === 'string' && !Object.hasOwn(message, 'id'), 'Unexpected server request')
        if (pendingId !== 2 || message.method !== 'notifications/progress'
          || message.params?.progressToken !== receipt.progressToken) return
        protocol(cursor(message.params.progress)
          && (message.params.message === undefined || typeof message.params.message === 'string'), 'Invalid matched progress')
        try {
          writeFileSync(files['progress.jsonl'], `${JSON.stringify(message)}\n`)
          receipt.progressCount += 1
        } catch (error) {
          fail('receipt-failure', 'Progress receipt write failed', error.code)
          return
        }
        try {
          onProgress(message)
        } catch {
          fail('transport-failure', 'Progress dispatch failed')
        }
        return
      }
      protocol(message.id === pendingId, 'Uncorrelated JSON-RPC response')
      const stage = pendingId === 1 ? 'initializeResponse' : 'finalResponse'
      receipt[stage] = message
      protocol(Object.hasOwn(message, 'result') !== Object.hasOwn(message, 'error'), 'Invalid response result/error')
      if (Object.hasOwn(message, 'error')) {
        protocol(object(message.error) && Number.isInteger(message.error.code)
          && typeof message.error.message === 'string', 'Invalid JSON-RPC error')
        if (pendingId === 2) receipt.waitOutcome = 'json-rpc-error'
        fail('json-rpc-error', pendingId === 1 ? 'Initialize returned an error' : 'run_wait returned an error', message.error.code)
        return
      }
      const result = message.result
      protocol(object(result), 'Invalid response result')
      if (pendingId === 1) {
        protocol(result.protocolVersion === PROTOCOL && object(result.capabilities)
          && object(result.capabilities.tools) && object(result.serverInfo)
          && typeof result.serverInfo.name === 'string' && typeof result.serverInfo.version === 'string', 'Unsupported initialize result')
        if (closing) {
          fail('process-failure', 'Owned MCP process exited during initialization')
          return
        }
        send({ jsonrpc: '2.0', method: 'notifications/initialized' })
        if (finished) return
        pendingId = 2
        send({
          jsonrpc: '2.0', id: 2, method: 'tools/call',
          params: {
            name: 'run_wait',
            arguments: { runId: options.runId, cursor: options.cursor, timeoutMs: options.waitMs, progress: true },
            _meta: { progressToken: receipt.progressToken },
          },
        })
        return
      }
      protocol(Array.isArray(result.content) && (result.isError === undefined || typeof result.isError === 'boolean'), 'Invalid tool result')
      if (object(result.structuredContent) && cursor(result.structuredContent.activityCursor)) {
        receipt.activityCursor = result.structuredContent.activityCursor
      }
      if (result.isError === true) {
        receipt.waitOutcome = 'tool-error'
      } else {
        protocol(object(result.structuredContent) && result.structuredContent.runId === options.runId
          && receipt.activityCursor !== UNKNOWN && typeof result.structuredContent.timedOut === 'boolean', 'Invalid run_wait projection')
        receipt.waitOutcome = result.structuredContent.timedOut ? 'timedOut' : 'returned'
      }
      finish()
    } catch (error) {
      fail('protocol-failure', error instanceof ProtocolFailure ? error.message : 'Malformed MCP stdout message')
    }
  }
  const abort = () => signal.reason === 'output-error'
    ? fail('transport-failure', 'Progress stdout failed') : fail('interrupted', 'Observation interrupted')
  signal?.addEventListener('abort', abort, { once: true })
  if (signal?.aborted) abort()
  try {
    if (!finished) {
      child = launch(options.node, [options.runnerEntry, 'mcp'], {
        cwd: options.project, stdio: ['pipe', 'pipe', 'pipe'],
      })
      receipt.server.pid = child.pid ?? UNKNOWN
      child.on('error', error => fail('process-failure', 'Owned MCP process failed to start or operate', error.code))
      child.on('exit', (code, exitSignal) => {
        if (sealed) return
        receipt.cleanup.exit = { code, signal: exitSignal }
        if (code !== 0 || exitSignal !== null) {
          receipt.failures.push({ kind: 'process-failure', detail: 'Owned MCP process exited unsuccessfully' })
        }
        // Drain already-buffered responses, but bound cleanup even if another process holds stdio.
        complete()
      })
      child.on('close', () => {
        if (sealed) return
        receipt.cleanup.streamsClosed = true
        if (!finished) fail('eof-failure', 'Owned MCP connection closed before the final response')
        closed()
      })
      child.stdin.on('error', error => fail('transport-failure', 'MCP stdin failed', error.code))
      child.stdout.on('error', error => fail('transport-failure', 'MCP stdout failed', error.code))
      child.stderr.on('error', error => fail('transport-failure', 'MCP stderr failed', error.code))
      child.stderr.on('data', chunk => {
        if (sealed) return
        receipt.stderr.observedBytes += chunk.length
        if (!stderrWritable) return
        const retained = chunk.subarray(0, STDERR_BYTES - receipt.stderr.retainedBytes)
        try {
          writeFileSync(files['stderr.log'], retained)
          receipt.stderr.retainedBytes += retained.length
        } catch (error) {
          stderrWritable = false
          fail('receipt-failure', 'Stderr receipt write failed', error.code)
        }
      })
      lines = createInterface({ input: child.stdout, crlfDelay: Infinity })
      lines.on('line', receive)
      lines.on('error', error => fail('transport-failure', 'MCP line reader failed', error.code))
      lines.on('close', () => {
        if (!finished) fail('eof-failure', 'MCP stdout ended before the final response')
      })
      send({
        jsonrpc: '2.0', id: 1, method: 'initialize',
        params: { protocolVersion: PROTOCOL, capabilities: {}, clientInfo: { name: 'wardpulse-run-wait-observer', version: '1.0.0' } },
      })
    }
    await response
  } catch (error) {
    fail('process-failure', 'Owned MCP connection could not be created', error.code)
  } finally {
    closing = true
    if (child) {
      try {
        child.stdin.end()
      } catch (error) {
        fail('transport-failure', 'Owned MCP stdin could not close normally', error.code)
      }
      let timer
      await Promise.race([
        connectionClosed,
        new Promise(resolveLimit => {
          timer = setTimeout(() => {
            receipt.cleanup.limitReached = true
            resolveLimit()
          }, CLEANUP_MS)
        }),
      ])
      clearTimeout(timer)
      if (!finished) fail('process-failure', 'Owned MCP process exited without a final response')
      // Release only local handles at the limit; never signal the server or durable run.
      lines?.close()
      child.stdin.destroy()
      child.stdout.destroy()
      child.stderr.destroy()
      child.unref()
    }
    signal?.removeEventListener('abort', abort)
    for (const name of ['progress.jsonl', 'stderr.log']) {
      if (name === 'stderr.log') {
        try {
          receipt.stderr.retainedBytes = fstatSync(files[name]).size
        } catch (error) {
          receipt.stderr.retainedBytes = UNKNOWN
          fail('receipt-failure', 'Stderr receipt size is unknown', error.code)
        }
      }
      try {
        closeSync(files[name])
      } catch (error) {
        fail('receipt-failure', `${name} close failed`, error.code)
      }
    }
    receipt.stderr.truncated = receipt.stderr.retainedBytes === UNKNOWN
      ? UNKNOWN : receipt.stderr.observedBytes > receipt.stderr.retainedBytes
    sealed = true
    try {
      writeFileSync(files['outcome.json'], `${JSON.stringify(receipt, null, 2)}\n`)
    } catch (error) {
      throw new Error(`Outcome receipt write failed (${error.code ?? 'Unknown'}); partial files are preserved`)
    } finally {
      closeSync(files['outcome.json'])
    }
  }
  return receipt
}

async function main() {
  const { values } = parseArgs({
    options: {
      node: { type: 'string' }, 'runner-entry': { type: 'string' }, project: { type: 'string' },
      'run-id': { type: 'string' }, cursor: { type: 'string' }, 'wait-ms': { type: 'string' }, output: { type: 'string' },
      'qualified-binding': { type: 'boolean' }, 'sole-observer': { type: 'boolean' },
    },
  })
  for (const name of ['node', 'runner-entry', 'project', 'run-id', 'cursor', 'wait-ms', 'output']) {
    if (!values[name]) throw new Error(`Missing --${name}`)
  }
  const controller = new AbortController()
  const interrupt = () => controller.abort()
  const outputError = () => {
    process.exitCode = 1
    controller.abort('output-error')
  }
  process.on('SIGINT', interrupt)
  process.on('SIGTERM', interrupt)
  process.stdout.on('error', outputError)
  try {
    const receipt = await observeRunWait({
      node: values.node, runnerEntry: values['runner-entry'], project: values.project,
      runId: values['run-id'], cursor: Number(values.cursor), waitMs: Number(values['wait-ms']), output: values.output,
      qualifiedBinding: values['qualified-binding'], soleObserver: values['sole-observer'],
    }, { signal: controller.signal, onProgress: message => process.stdout.write(`${JSON.stringify(message)}\n`) })
    if (!['returned', 'timedOut'].includes(receipt.waitOutcome) || receipt.failures.length
      || receipt.cleanup.exit === UNKNOWN || receipt.cleanup.limitReached) process.exitCode = 1
  } finally {
    process.off('SIGINT', interrupt)
    process.off('SIGTERM', interrupt)
    // Keep handling errors from any progress bytes still buffered by stdout until CLI exit.
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(error.message)
    process.exitCode = 1
  })
}
