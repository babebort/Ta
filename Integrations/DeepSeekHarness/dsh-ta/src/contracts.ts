export type JSONValue =
  | null
  | boolean
  | number
  | string
  | JSONValue[]
  | { [key: string]: JSONValue }

export type TaMethod =
  | 'system.status'
  | 'system.capabilities'
  | 'system.permissions'
  | 'target.listDisplays'
  | 'target.listWindows'
  | 'capture.display'
  | 'capture.frontmost'
  | 'capture.window'
  | 'capture.region'
  | 'recognize.ocr'
  | 'analyze.image'
  | 'translate.text'
  | 'translate.image'
  | 'deliver.copy'
  | 'deliver.save'

export interface TaArtifact {
  id: string
  path: string
  mimeType: string
  width?: number
  height?: number
  bytes: number
  sha256: string
  expiresAt: string
}

export interface TaErrorPayload {
  code: string
  message: string
  hint?: string
  retryable: boolean
}

export interface TaResponse {
  protocolVersion: number
  requestId: string
  ok: boolean
  data?: JSONValue
  artifacts: TaArtifact[]
  meta?: {
    durationMs: number
    cloudUploaded: boolean
  }
  error?: TaErrorPayload
}

export interface TaRequest {
  protocolVersion: 1
  requestId: string
  method: TaMethod
  params: Record<string, JSONValue>
  client: {
    name: 'dsh-ta'
    version: '1.0.1'
  }
}

export class TaResponseError extends Error {
  readonly code: string
  readonly hint: string | undefined
  readonly retryable: boolean

  constructor(payload: TaErrorPayload) {
    super(payload.hint ? `${payload.message} ${payload.hint}` : payload.message)
    this.name = 'TaResponseError'
    this.code = payload.code
    this.hint = payload.hint
    this.retryable = payload.retryable
  }
}
