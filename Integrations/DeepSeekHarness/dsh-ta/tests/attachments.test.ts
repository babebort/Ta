import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import type { AttachmentStore, ImageAttachmentRef, SaveImageAttachment } from '@deepseek-ai/dsh-attachment'
import { importArtifacts } from '../src/attachments.js'
import type { TaArtifact } from '../src/contracts.js'

test('Ta artifacts are durably imported through the Harness attachment store', async () => {
  const root = await mkdtemp(join(tmpdir(), 'dsh-ta-attachment-'))
  try {
    const path = join(root, 'capture.png')
    const bytes = Buffer.from('fixture-png')
    await writeFile(path, bytes)
    const observed: SaveImageAttachment[] = []
    const expected = {
      attachmentId: 'sha256:test',
      mediaType: 'image/png',
      bytes: bytes.length,
      width: 4,
      height: 3,
      name: 'capture.png',
    } as ImageAttachmentRef
    const store = {
      imageLimits: { mediaTypes: ['image/png'] },
      async saveImage(input: SaveImageAttachment) {
        observed.push(input)
        return expected
      },
    } as AttachmentStore
    const artifact: TaArtifact = {
      id: 'artifact-1', path, mimeType: 'image/png', bytes: bytes.length,
      width: 4, height: 3,
      sha256: createHash('sha256').update(bytes).digest('hex'),
      expiresAt: '2026-08-26T00:00:00Z',
    }

    const imported = await importArtifacts([artifact], store)

    assert.deepEqual(imported, [expected])
    assert.deepEqual(Buffer.from(observed[0]!.data), bytes)
    assert.equal(observed[0]!.mediaType, 'image/png')
    assert.equal(observed[0]!.name, 'capture.png')
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
