import netrc from 'netrc-parser';
import Debug from 'debug';
import {
  vars,
  loginUser,
  logger,
  Auth,
  LocaleTypes,
  color,
  AuthTokenType,
  AUTH_TOKEN_TYPE_KEY,
  BaseApiService,
  buildAuthHeaders,
  getUrlWithAdTag,
} from '@tencent/gongfeng-cli-base';
import * as inquirer from 'inquirer';
import * as ora from 'ora';
import { getTicket, IoaTicket } from '@tencent/gongfeng-ioa-login';
import * as os from 'os';
import { AxiosInstance } from 'axios';
import * as qs from 'qs';

enum LoginMethType {
  IOA = 'ioa',
  TOKEN = 'token',
  BROWSER = 'browser',
}
const debug = Debug('gongfeng:auth-user');

export class AuthUser {
  auth: Auth;
  currentHost = '';
  loginHost = '';
  protocol = '';
  api: AxiosInstance;

  constructor(locale: LocaleTypes, api: AxiosInstance) {
    this.currentHost = vars.host();
    this.loginHost = process.env.GONGFENG_LOGIN_HOST || this.currentHost;
    this.protocol = this.loginHost.startsWith('localhost') ? 'http' : 'https';
    this.auth = new Auth(locale);
    this.api = api;
  }

  async login(tokenFromFlag?: string) {
    try {
      const user = await loginUser();
      if (user) {
        const answer = await inquirer.prompt({
          type: 'confirm',
          name: 'confirm',
          message: __('continueLogin'),
          default: true,
        });
        if (!answer.confirm) {
          return;
        }
        await this.logout();
      }

      // 如果用户有输入 token，则直接通过 token 登录
      if (tokenFromFlag) {
        await this.loginWithToken(tokenFromFlag);
      } else if (os.platform() === 'win32' || os.platform() === 'darwin') {
        const answer = await inquirer.prompt({
          type: 'list',
          name: 'confirm',
          message: __('selectLoginMethod'),
          choices: [
            {
              name: __('ioaLoginMethod'),
              value: LoginMethType.IOA,
            },
            {
              name: __('browserLoginMethod'),
              value: LoginMethType.BROWSER,
            },
            {
              name: __('tokenLoginMethod'),
              value: LoginMethType.TOKEN,
            },
          ],
        });
        switch (answer.confirm) {
          case LoginMethType.IOA:
            await this.loginWithIoa();
            return;
          case LoginMethType.TOKEN: {
            const token = await this.getTokenFromPrompt();
            await this.loginWithToken(token);
            return;
          }
          default:
            await this.loginWithBrowser();
            return;
        }
      } else {
        await this.loginWithBrowser();
      }
    } catch (e) {
      logger.error('login failed', e);
    }
  }

  printUser(username: string) {
    console.log(__('loggedInUser', { username: color.bold(color.success(username)) }));
  }

  /**
   * 通过浏览器 oauth2 登录
   */
  async loginWithBrowser() {
    const authResponse = await this.auth.browser();
    if (authResponse !== null) {
      await this.saveToken(authResponse.accessToken, authResponse.refreshToken, authResponse.username);
      this.printUser(authResponse.username);
    }
  }

  /**
   * 通过 iOA 登录
   */
  async loginWithIoa() {
    const ioaSpinner = ora().start(__('ioaLogin'));
    try {
      const ioaTicket = getTicket();
      if (ioaTicket?.ticket && ioaTicket.errCode === '0') {
        const authResponse = await this.ioaLogin(ioaTicket);
        if (authResponse !== null) {
          await this.saveToken(authResponse.accessToken, authResponse.refreshToken, authResponse.username);
          this.printUser(authResponse.username);
        }
      } else {
        console.log(color.error(__('ioaTokenFailed')));
        logger.error(`ioa ticket failed: ${JSON.stringify(ioaTicket)}`);
        if (ioaTicket?.error) {
          console.log(ioaTicket.error);
        }
      }
    } catch (e) {
      logger.error(`get ioaTicket error: ${JSON.stringify(e)}`);
      debug(`get ioaTicket error: ${JSON.stringify(e)}`);
      console.log(color.error(__('ioaLoginFailed')));
    } finally {
      ioaSpinner.stop();
    }
  }

  async loginWithToken(token: string) {
    // 调用接口获取用户信息，并输出用户名
    const baseApiService = new BaseApiService(this.api);
    try {
      const headersWithToken = await buildAuthHeaders(AuthTokenType.PERSONAL_TOKEN, token);
      const { user } = await baseApiService.getCurrentUser(undefined, headersWithToken);
      const username = user?.username ?? '';
      if (!username) {
        console.log(color.error(__('tokenLoginError')));
        return;
      }
      console.log(__('loggedIn', { username: color.bold(color.success(username)) }));
      // 将登录用户信息写入配置文件
      await this.saveToken(token, '', username, AuthTokenType.PERSONAL_TOKEN);
    } catch (error) {
      console.log(color.error(__('tokenLoginError')));
      // 如果获取用户信息失败，则说明没有登录成功，清空对应环境 token
      await this.saveToken('', '', '');
    }
  }

  /**
   * 退出登录
   */
  async logout() {
    debug(`logout host:${this.currentHost}`);
    await netrc.load();
    const netrcHost = netrc.machines[this.currentHost];
    // 如果用户已登出，则 netrcHost 会为空，直接返回。
    if (!netrcHost) return;
    const username = netrcHost.login ?? '';
    if (username) {
      delete netrc.machines[this.currentHost];
      await netrc.save();
      console.log(__('logoutSuccess', { username }));
      debug(`logout host:${this.currentHost} success`);
    }
  }

  private async saveToken(
    authToken: string,
    refreshToken: string,
    username: string,
    authTokenType = AuthTokenType.ACCESS_TOKEN,
  ) {
    const host = vars.host();
    await netrc.load();
    if (!netrc.machines[host]) {
      netrc.machines[host] = {};
    }
    netrc.machines[host].login = username;
    netrc.machines[host].password = authToken;
    netrc.machines[host].refresh = refreshToken;
    netrc.machines[host][AUTH_TOKEN_TYPE_KEY] = authTokenType;
    await netrc.save();
  }

  private async ioaLogin(ticket: IoaTicket) {
    const loginSpinner = ora().start(__('loggingIn'));
    try {
      const authToken = await this.getToken(ticket);
      if (!authToken.access_token) {
        console.log(__('accessTokenError'));
        return null;
      }
      const headersWithToken = await buildAuthHeaders(AuthTokenType.ACCESS_TOKEN, authToken.access_token);
      const { data: result } = await this.api.get(`https://${this.currentHost}/api/web/v1/users/session/route`, {
        headers: headersWithToken as any,
      });
      loginSpinner.stop();
      return {
        accessToken: authToken.access_token,
        refreshToken: authToken.refresh_token,
        username: result.user.username,
      };
    } catch (err: any) {
      // console.log(err);
      logger.error('get ioa token failed:', JSON.stringify(err));
      console.log(color.error(__('loginError')));
      return null;
    } finally {
      loginSpinner.stop();
    }
  }

  private async getToken(ticket: IoaTicket) {
    const appId = vars.oauthAppId();
    const { data: authToken } = await this.api.post(
      `${this.protocol}://${this.loginHost}/oauth/device/ioa`,
      qs.stringify({
        client_id: appId,
        username: ticket.username,
        token: ticket.ticket,
        device_id: ticket.deviceId,
      }),
    );
    return authToken;
  }

  private async getTokenFromPrompt() {
    const accessTokenUrl = getUrlWithAdTag(`https://${vars.host()}/profile/account`);
    console.log(__('getPersonalAccessToken', { accessTokenUrl }));
    const { token } = await inquirer.prompt({
      type: 'password',
      name: 'token',
      message: __('inputToken'),
    });
    return token;
  }
}
