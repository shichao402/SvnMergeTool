import BaseCommand from '../../base';
// @ts-ignore
import { CONFIG_FILE, file, preAuth, LocaleTypes } from '@tencent/gongfeng-cli-base';
import { AuthUser } from '../../auth';
import * as path from 'path';
import { Flags } from '@oclif/core';

export default class AuthLogin extends BaseCommand {
  static summary = '登录工蜂';
  static description = `不带任何参数时，工蜂CLI会通过交互的方式引导登录，这种模式下支持3种登录方式：
  1. 通过IOA登录；
  2. 打开Web浏览器输入设备码；
  3. 输入Token（oauth2 access token或者personal access token）。

  此外，也可以执行‘gf auth login --token xxx’，直接从标准输入中获取token登录工蜂。

  最后，如果将token定义在了环境变量中“xxx”，工蜂CLI会直接使用环境变量的值进行认证而无需执行登录命令，此方式适用于流水线等自动化场景。`;
  static examples = ['gf auth login'];
  static aliases = ['login'];

  static flags = {
    token: Flags.string({
      char: 't',
      description: '从标准输入中获取token进行登录。',
      required: false,
    }),
  };

  @preAuth({ skip: true })
  public async run(): Promise<void> {
    const { flags } = await this.parse(AuthLogin);
    let locale = LocaleTypes.ZH;
    const configFile = path.join(this.config.dataDir, CONFIG_FILE);
    if (file.existsSync(configFile)) {
      const config = file.readJsonSync(configFile);
      locale = config.locale || LocaleTypes.ZH;
    }
    const auth = new AuthUser(locale, this.api);
    await auth.login(flags.token);
  }
}
