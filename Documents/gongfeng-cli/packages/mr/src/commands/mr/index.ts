import { Command } from '@oclif/core';
import { GongFengHelp } from '@tencent/gongfeng-cli-base';

export default class Mr extends Command {
  static summary = '工蜂合并请求管理';
  static usage = 'mr <command> [flags]';
  static examples = ['gf mr list', 'gf mr create', 'gf mr show 3', 'gf mr close 1', 'gf mr reopen dev'];

  async run(): Promise<void> {
    const help = new GongFengHelp(this.config);
    await help.showHelp(['mr']);
  }
}
