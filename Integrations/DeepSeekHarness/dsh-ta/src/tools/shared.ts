import type { ImageAttachmentRef } from '@deepseek-ai/dsh-attachment'
import type { JSONValue } from '../contracts.js'
import type { TaToolValue } from '../runtime.js'

export const taToolOutputSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    requestId: { type: 'string', required: true },
    data: { type: 'json' },
    artifacts: {
      type: 'array',
      required: true,
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          taArtifactId: { type: 'string', required: true },
          mimeType: { type: 'string', required: true },
          width: { type: 'integer' },
          height: { type: 'integer' },
          bytes: { type: 'integer', required: true },
          sha256: { type: 'string', required: true },
          expiresAt: { type: 'string', required: true },
          attachment: {
            type: 'object',
            required: true,
            additionalProperties: false,
            properties: {
              attachmentId: { type: 'string', required: true },
              mediaType: {
                type: 'string',
                enum: ['image/png', 'image/jpeg', 'image/webp', 'image/gif'],
                required: true,
              },
              bytes: { type: 'integer', required: true },
              width: { type: 'integer', required: true },
              height: { type: 'integer', required: true },
              name: { type: 'string' },
            },
          },
        },
      },
    },
    meta: {
      type: 'object',
      additionalProperties: false,
      properties: {
        durationMs: { type: 'integer', required: true },
        cloudUploaded: { type: 'boolean', required: true },
      },
    },
  },
} as const

export function renderTaToolValue(value: TaToolValue) {
  const content: Array<
    | { type: 'text'; text: string }
    | { type: 'image'; attachment: ImageAttachmentRef }
  > = [{ type: 'text', text: JSON.stringify(value) }]
  for (const artifact of value.artifacts) {
    content.push({
      type: 'image',
      attachment: artifact.attachment as unknown as ImageAttachmentRef,
    })
  }
  return content
}

export function requireInteger(value: number | undefined, name: string): number {
  if (value === undefined || !Number.isInteger(value) || value < 0 || value > 4_294_967_295) {
    throw new Error(`${name} must be an integer from 0 through 4294967295.`)
  }
  return value
}

export function requireFinite(value: number | undefined, name: string): number {
  if (value === undefined || !Number.isFinite(value)) {
    throw new Error(`${name} must be a finite number.`)
  }
  return value
}

export function requirePositive(value: number | undefined, name: string): number {
  const result = requireFinite(value, name)
  if (result <= 0) throw new Error(`${name} must be greater than zero.`)
  return result
}

export function requireText(value: string | undefined, name: string): string {
  if (value === undefined || value.trim().length === 0) {
    throw new Error(`${name} must be a non-empty string.`)
  }
  return value
}

export function dataString(data: JSONValue | undefined, key: string): string | undefined {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return undefined
  const value = data[key]
  return typeof value === 'string' ? value : undefined
}
