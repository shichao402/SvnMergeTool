import { Command } from '@oclif/core';
import { GongFengHelp } from '@tencent/gongfeng-cli-base';

export default class Issue extends Command {
  static description = '工蜂issue管理';
  static usage = 'issue <command> [flags]';
  static examples = ['gf issue list --label "feature"', 'gf issue show 1 -w'];

  async run(): Promise<void> {
    const help = new GongFengHelp(this.config);
    await help.showHelp(['issue']);
  }
}
