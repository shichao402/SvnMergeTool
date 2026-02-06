import BaseCommand from '../../base';
import { createEnv } from 'yeoman-environment';
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { preAuth } from '@tencent/gongfeng-cli-base';
import { Args } from '@oclif/core';

/**
 * 用于自动生成符合工蜂 CLI 开发标准的 CLI 插件项目
 */
export default class Create extends BaseCommand {
  static description = `用于自动生成工蜂 CLI 的子命令或者工蜂 CLI 的插件项目
  此命令会克隆 'code/hello-cli' 项目，并更新该项目中的信息`;

  static hidden = true;

  static examples = ['$ gf extension create { subCommand }'];

  static args = {
    name: Args.string({
      description: 'directory name of new command or plugin',
      required: true,
    }),
  };

  @preAuth({ skip: true })
  async run(): Promise<void> {
    const { args } = await this.parse(Create);
    const env = createEnv();
    env.register(require.resolve('../../generators/cli'), 'gflif:cli');
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    await env.run('gflif:cli', {
      name: args.name,
      force: true,
    });
  }
}
