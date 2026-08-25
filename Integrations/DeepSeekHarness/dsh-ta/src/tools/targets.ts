import type { Context } from '@deepseek-ai/cordis'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { TaToolRuntime } from '../runtime.js'
import { renderTaToolValue, taToolOutputSchema } from './shared.js'

export function registerTargetTool(ctx: Context, runtime: TaToolRuntime): void {
  ctx.tools.register(defineTool({
    name: 'ta_list_targets',
    description: 'List visible displays or windows before capturing an exact target. App accepts a visible name fragment or Bundle ID.',
    parameters: {
      kind: { type: 'string', enum: ['displays', 'windows'], required: true },
      app: { type: 'string', description: 'Optional app name fragment or exact Bundle ID for window listing.' },
    },
    output: {
      schema: taToolOutputSchema,
      render: (_args, value) => renderTaToolValue(value),
    },
    isConcurrencySafe: () => true,
    async execute(args, exec) {
      if (args.kind === 'displays') return runtime.call('target.listDisplays', {}, exec.signal)
      return runtime.call('target.listWindows', args.app === undefined ? {} : { app: args.app }, exec.signal)
    },
  }))
}
