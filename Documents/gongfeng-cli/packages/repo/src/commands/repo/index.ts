import { Command } from '@oclif/core';
import { GongFengHelp } from '@tencent/gongfeng-cli-base';

export default class Repo extends Command {
  static summary = '工蜂仓库管理';
  static usage = 'repo <command> [flags]';
  static examples = ['gf repo show -w', 'gf repo clone code/cli'];

  async run(): Promise<void> {
    const help = new GongFengHelp(this.config);
    await help.showHelp(['repo']);
  }
}
