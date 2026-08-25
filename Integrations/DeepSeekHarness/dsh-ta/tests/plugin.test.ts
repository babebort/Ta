import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Context } from '@deepseek-ai/cordis'
import { apply, defaultConfig } from '../src/index.js'

test('Cordis apply registers only Bridge v1 capabilities with canonical output schemas', () => {
  const definitions: Array<Record<string, unknown>> = []
  const ctx = {
    tools: { register(definition: Record<string, unknown>) { definitions.push(definition) } },
    attachments: {},
    get() { return undefined },
  } as unknown as Context

  apply(ctx, { ...defaultConfig, autoLaunch: false })

  const names = definitions.map(definition => definition.name)
  assert.deepEqual(names, [
    'ta_system', 'ta_list_targets', 'ta_capture', 'ta_ocr',
    'ta_analyze', 'ta_translate', 'ta_deliver',
  ])
  for (const definition of definitions) {
    assert.equal(typeof definition.description, 'string')
    assert.ok(definition.parameters)
    assert.ok(definition.output)
  }
  assert.ok(!names.includes('ta_transform'))

  const capture = definitions.find(definition => definition.name === 'ta_capture')!
  const content = (capture.output as { render: (args: unknown, value: unknown) => unknown[] }).render({}, {
    requestId: 'req-1',
    artifacts: [{
      taArtifactId: 'artifact-1', mimeType: 'image/png', bytes: 10,
      sha256: 'abc', expiresAt: '2026-08-26T00:00:00Z',
      attachment: {
        attachmentId: 'sha256:test', mediaType: 'image/png', bytes: 10,
        width: 4, height: 3,
      },
    }],
  })
  assert.equal((content[0] as { type: string }).type, 'text')
  assert.equal((content[1] as { type: string }).type, 'image')
  assert.ok(!JSON.stringify(content).includes('/Users/'))
})
