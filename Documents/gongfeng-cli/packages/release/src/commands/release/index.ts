import { Command } from '@oclif/core';
import { GongFengHelp } from '@tencent/gongfeng-cli-base';

export default class Release extends Command {
  static summary = '工蜂 release 管理';
  static usage = 'release <command> [flags]';
  static examples = ['gf release list', 'gf release show v1.5.0'];

  async run(): Promise<void> {
    const help = new GongFengHelp(this.config);
    await help.showHelp(['release']);
  }
}
