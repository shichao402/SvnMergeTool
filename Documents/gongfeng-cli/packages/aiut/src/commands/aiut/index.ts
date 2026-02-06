import { Command } from '@oclif/core';
import { GongFengHelp } from '@tencent/gongfeng-cli-base';

export default class Aiut extends Command {
  static summary = '工蜂AI单测';
  static usage = 'aiut <command> [flags]';
  static examples = ['gf aiut run path', 'gf aiut fix path'];

  async run(): Promise<void> {
    const help = new GongFengHelp(this.config);
    await help.showHelp(['aiut']);
  }
}
