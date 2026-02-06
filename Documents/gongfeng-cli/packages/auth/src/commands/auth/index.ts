import { Command } from '@oclif/core';
import { GongFengHelp } from '@tencent/gongfeng-cli-base';

export default class Auth extends Command {
  static summary = '工蜂账号管理';
  static usage = 'auth <command> [flags]';

  async run(): Promise<void> {
    const help = new GongFengHelp(this.config);
    await help.showHelp(['auth']);
  }
}
