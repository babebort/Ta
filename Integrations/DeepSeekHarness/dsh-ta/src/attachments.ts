import { createHash } from 'node:crypto'
import { readFile, realpath } from 'node:fs/promises'
import { basename, isAbsolute } from 'node:path'
import type {
  AttachmentStore,
  ImageAttachmentRef,
  ImageMediaType,
} from '@deepseek-ai/dsh-attachment'
import type { TaArtifact } from './contracts.js'

const IMAGE_TYPES = new Set<ImageMediaType>([
  'image/png', 'image/jpeg', 'image/webp', 'image/gif',
])

export async function importArtifacts(
  artifacts: readonly TaArtifact[],
  store: AttachmentStore,
  signal?: AbortSignal,
): Promise<ImageAttachmentRef[]> {
  const imported: ImageAttachmentRef[] = []
  for (const artifact of artifacts) {
    if (!isAbsolute(artifact.path)) throw new Error('Ta returned a non-absolute artifact path.')
    if (!isImageMediaType(artifact.mimeType)) {
      throw new Error(`Ta returned unsupported artifact type ${artifact.mimeType}.`)
    }
    if (!store.imageLimits.mediaTypes.includes(artifact.mimeType)) {
      throw new Error(`Harness does not accept ${artifact.mimeType} attachments.`)
    }
    const verifiedPath = await realpath(artifact.path)
    const data = await readFile(verifiedPath, { signal })
    if (data.byteLength !== artifact.bytes) {
      throw new Error(`Ta artifact ${artifact.id} changed size before import.`)
    }
    const digest = createHash('sha256').update(data).digest('hex')
    if (digest !== artifact.sha256.toLowerCase()) {
      throw new Error(`Ta artifact ${artifact.id} failed SHA-256 verification.`)
    }
    imported.push(await store.saveImage({
      data,
      mediaType: artifact.mimeType,
      name: basename(verifiedPath),
    }))
  }
  return imported
}

function isImageMediaType(value: string): value is ImageMediaType {
  return IMAGE_TYPES.has(value as ImageMediaType)
}
