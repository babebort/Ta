import type { Context } from '@deepseek-ai/cordis'
import type { AttachmentStore } from '@deepseek-ai/dsh-attachment'
import { TaBridgeClient } from './bridge-client.js'
import { Config, defaultConfig, type Config as TaConfig } from './config.js'
import { TaToolRuntime } from './runtime.js'
import { registerCaptureTool } from './tools/capture.js'
import { registerDeliverTool } from './tools/deliver.js'
import { registerRecognizeTools } from './tools/recognize.js'
import { registerSystemTool } from './tools/system.js'
import { registerTargetTool } from './tools/targets.js'
import { registerTranslateTool } from './tools/translate.js'

export const name = 'dsh-ta'
export const inject = ['tools', 'attachments']
export { Config, defaultConfig }
export type { TaConfig as ConfigType }

export function apply(ctx: Context, config: TaConfig = defaultConfig): void {
  const attachments = (ctx as Context & { attachments: AttachmentStore }).attachments
  const bridge = new TaBridgeClient({
    socketPath: config.socketPath,
    appPath: config.appPath,
    timeoutMs: config.timeoutMs,
    autoLaunch: config.autoLaunch,
  })
  const runtime = new TaToolRuntime(bridge, attachments)
  registerSystemTool(ctx, runtime)
  registerTargetTool(ctx, runtime)
  registerCaptureTool(ctx, runtime)
  registerRecognizeTools(ctx, runtime, config)
  registerTranslateTool(ctx, runtime, config)
  registerDeliverTool(ctx, runtime, config)
}
