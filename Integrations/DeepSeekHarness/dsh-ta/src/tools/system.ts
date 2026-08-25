import type { Context } from '@deepseek-ai/cordis'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { TaMethod } from '../contracts.js'
import type { TaToolRuntime } from '../runtime.js'
import { renderTaToolValue, taToolOutputSchema } from './shared.js'

export function registerSystemTool(ctx: Context, runtime: TaToolRuntime): void {
  ctx.tools.register(defineTool({
    name: 'ta_system',
    description: 'Inspect Ta Bridge status, supported methods, or macOS/model permissions. Never returns API keys.',
    parameters: {
      action: {
        type: 'string', required: true,
        enum: ['status', 'capabilities', 'permissions'],
      },
    },
    output: {
      schema: taToolOutputSchema,
      render: (_args, value) => renderTaToolValue(value),
    },
    isConcurrencySafe: () => true,
    async execute(args, exec) {
      const methods: Record<typeof args.action, TaMethod> = {
        status: 'system.status', capabilities: 'system.capabilities', permissions: 'system.permissions',
      }
      return runtime.call(methods[args.action], {}, exec.signal)
    },
  }))
}
