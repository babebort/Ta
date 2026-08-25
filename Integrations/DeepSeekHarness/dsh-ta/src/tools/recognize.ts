import type { Context } from '@deepseek-ai/cordis'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { Config } from '../config.js'
import type { JSONValue } from '../contracts.js'
import type { TaToolRuntime } from '../runtime.js'
import { renderTaToolValue, taToolOutputSchema } from './shared.js'

const CLOUD = ['auto', 'allow', 'deny'] as const

export function registerRecognizeTools(ctx: Context, runtime: TaToolRuntime, config: Config): void {
  ctx.tools.register(defineTool({
    name: 'ta_ocr',
    description: 'Extract text from the latest or a named Ta artifact using the OCR engine configured in Ta. Prefer this local path before cloud analysis.',
    parameters: {
      artifactId: { type: 'string', description: 'Ta artifact ID returned by ta_capture; omit for the latest artifact.' },
      languages: { type: 'array', items: { type: 'string' } },
      mergeWrappedLines: { type: 'boolean' },
    },
    output: {
      schema: taToolOutputSchema,
      render: (_args, value) => renderTaToolValue(value),
    },
    async execute(args, exec) {
      const params: Record<string, JSONValue> = runtime.imageParams(args.artifactId)
      if (args.languages !== undefined) params.languages = args.languages
      if (args.mergeWrappedLines !== undefined) params.mergeWrappedLines = args.mergeWrappedLines
      return runtime.call('recognize.ocr', params, exec.signal)
    },
  }))

  ctx.tools.register(defineTool({
    name: 'ta_analyze',
    description: 'Use Ta configured multimodal model for semantic image understanding, code explanation, table Markdown, or formula LaTeX. This may upload the image to cloud.',
    parameters: {
      artifactId: { type: 'string', description: 'Ta artifact ID returned by ta_capture; omit for the latest artifact.' },
      task: {
        type: 'string', enum: ['general', 'extractText', 'explainCode', 'tableMarkdown', 'formulaLaTeX'],
      },
      cloud: { type: 'string', enum: CLOUD },
    },
    output: {
      schema: taToolOutputSchema,
      render: (_args, value) => renderTaToolValue(value),
    },
    async execute(args, exec) {
      const params: Record<string, JSONValue> = {
        ...runtime.imageParams(args.artifactId),
        cloud: args.cloud ?? config.defaultCloud,
      }
      if (args.task !== undefined) params.task = args.task
      return runtime.call('analyze.image', params, exec.signal)
    },
  }))
}
