import { Command } from '@oclif/core';
import { GongFengHelp } from '@tencent/gongfeng-cli-base';

export default class Repo extends Command {
  static summary = '工蜂AICR';
  static usage = 'aicr <command> [flags]';
  static examples = ['gf aicr diff', 'gf aicr commit'];

  async run(): Promise<void> {
    const help = new GongFengHelp(this.config);
    await help.showHelp(['aicr']);
  }
}
