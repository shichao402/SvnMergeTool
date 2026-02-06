import { Command } from '@oclif/core';
import { GongFengHelp } from '@tencent/gongfeng-cli-base';

export default class Cr extends Command {
  static summary = '工蜂代码评审管理';
  static usage = 'cr <command> [flags]';
  static examples = ['gf cr list', 'gf cr create', 'gf cr close 1', 'gf cr reopen 13'];

  async run(): Promise<void> {
    const help = new GongFengHelp(this.config);
    await help.showHelp(['cr']);
  }
}
