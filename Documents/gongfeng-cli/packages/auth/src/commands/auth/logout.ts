import BaseCommand from '../../base';
import { AuthUser } from '../../auth';
// @ts-ignore
import { CONFIG_FILE, file, LocaleTypes, preAuth } from '@tencent/gongfeng-cli-base';
import * as path from 'path';

export default class AuthLogout extends BaseCommand {
  static summary = '退出账号';
  static examples = ['gf auth logout'];

  static aliases = ['logout'];

  @preAuth({ skip: true })
  public async run(): Promise<void> {
    let locale = LocaleTypes.ZH;
    const configFile = path.join(this.config.dataDir, CONFIG_FILE);
    if (file.existsSync(configFile)) {
      const config = file.readJsonSync(configFile);
      locale = config.locale || LocaleTypes.ZH;
    }
    const auth = new AuthUser(locale, this.api);
    await auth.logout();
  }
}
