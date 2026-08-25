import type { Context } from '@deepseek-ai/cordis'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { JSONValue, TaMethod } from '../contracts.js'
import type { TaToolRuntime } from '../runtime.js'
import {
  renderTaToolValue,
  requireFinite,
  requireInteger,
  requirePositive,
  taToolOutputSchema,
} from './shared.js'

export function registerCaptureTool(ctx: Context, runtime: TaToolRuntime): void {
  ctx.tools.register(defineTool({
    name: 'ta_capture',
    description: 'Silently capture the foreground window, a display, an exact window ID, or known global region without activating Ta or moving the pointer.',
    parameters: {
      target: { type: 'string', enum: ['frontmost', 'display', 'window', 'region'], required: true },
      displayId: { type: 'integer' },
      windowId: { type: 'integer' },
      x: { type: 'number' },
      y: { type: 'number' },
      width: { type: 'number' },
      height: { type: 'number' },
    },
    output: {
      schema: taToolOutputSchema,
      render: (_args, value) => renderTaToolValue(value),
    },
    async execute(args, exec) {
      let method: TaMethod
      let params: Record<string, JSONValue> = {}
      switch (args.target) {
        case 'frontmost':
          method = 'capture.frontmost'
          break
        case 'display':
          method = 'capture.display'
          if (args.displayId !== undefined) params.displayId = requireInteger(args.displayId, 'displayId')
          break
        case 'window':
          method = 'capture.window'
          params.windowId = requireInteger(args.windowId, 'windowId')
          break
        case 'region':
          method = 'capture.region'
          params = {
            displayId: requireInteger(args.displayId, 'displayId'),
            x: requireFinite(args.x, 'x'),
            y: requireFinite(args.y, 'y'),
            width: requirePositive(args.width, 'width'),
            height: requirePositive(args.height, 'height'),
          }
          break
      }
      return runtime.call(method, params, exec.signal)
    },
  }))
}
