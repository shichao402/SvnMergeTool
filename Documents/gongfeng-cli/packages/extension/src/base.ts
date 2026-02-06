import { Command } from '@oclif/core';
import * as path from 'path';
import * as i18n from 'i18n';
import { CONFIG_FILE, file, checkAuth, color } from '@tencent/gongfeng-cli-base';
import 'reflect-metadata';

export default abstract class BaseCommand extends Command {
  async init() {
    const skip = Reflect.getMetadata('skip', this, 'run');
    if (!skip) {
      const authed = await checkAuth();
      if (!authed) {
        console.log(color.bold(color.warn('使用工蜂CLI前，请先执行"gf auth login" (别名: "gf login")登录工蜂CLI')));
        this.exit(0);
        return;
      }
    }
    const configFile = path.join(this.config.dataDir, CONFIG_FILE);
    const config = file.readJsonSync(configFile);
    const locale = config.locale || 'zh';
    i18n.configure({
      locales: ['en', 'zh'],
      directory: path.join(__dirname, 'locales'),
      register: global,
    });
    i18n.setLocale(locale);
  }
  async catch(err: any) {
    // add any custom logic to handle errors from the command
    // or simply return the parent class error handling
    return super.catch(err);
  }
  async finally(err: any) {
    // called after run and catch regardless of whether or not the command errored
    return super.finally(err);
  }
}
