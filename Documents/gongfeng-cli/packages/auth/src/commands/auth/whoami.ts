import BaseCommand from '../../base';
// @ts-ignore
import { preAuth, color, loginUser, BaseApiService } from '@tencent/gongfeng-cli-base';

export default class Whoami extends BaseCommand {
  static summary = '显示当前登录账号的信息';

  static aliases = ['whoami'];

  @preAuth({ skip: true })
  public async run(): Promise<void> {
    let user = await loginUser();
    if (!user) {
      const baseService = new BaseApiService(this.api);
      try {
        const currentUser = await baseService.getCurrentUser();
        user = currentUser?.user?.username ?? '';
      } catch (e) {}
    }

    if (!user) {
      console.log(color.error(__('notLoggedIn')));
      this.exit(100);
      return;
    }
    console.log(__('loggedIn', { username: color.bold(color.success(user)) }));
  }
}
