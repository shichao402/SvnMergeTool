import netrc from 'netrc-parser';
import Debug from 'debug';
import { vars } from '../vars';
import color from '../color';
import { loginUser } from '../pre-auth';
import logger from '../logger';
import { ux } from '@oclif/core';
import axios, { AxiosError, AxiosResponse } from 'axios';
import * as qs from 'qs';
import * as os from 'os';
import * as Sentry from '@sentry/node';
import * as QRCode from 'qrcode';
import * as inquirer from 'inquirer';
import { I18n } from 'i18n';
import * as path from 'path';
import { exec } from '../shell';
import * as open from 'open';

interface OauthCode {
  device_code: string;
  user_code: string;
  verification_uri: string;
  expires_in: string;
  interval: string;
}

interface AuthToken {
  access_token: string;
  refresh_token: string;
  scope: string;
  token_type: string;
  expires_in: string;
}

export interface AuthResponse {
  accessToken: string;
  refreshToken: string;
  username: string;
}

export enum LocaleTypes {
  ZH = 'zh',
  EN = 'en',
}

export enum AuthTokenType {
  PERSONAL_TOKEN = 'personalToken',
  ACCESS_TOKEN = 'accessToken',
}

export const AUTH_TOKEN_TYPE_KEY = 'authTokenType';

const debug = Debug('gongfeng:auth');
const api = axios.create({
  timeout: 20000,
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
});

api.interceptors.response.use(
  (response: AxiosResponse) => response,
  (error: AxiosError) => {
    Sentry.captureException(error);
    return Promise.reject(error);
  },
);

export class Auth {
  currentHost = '';
  loginHost = '';
  protocol = '';
  i18n: I18n;

  constructor(locale?: LocaleTypes) {
    this.currentHost = vars.host();
    this.loginHost = process.env.GONGFENG_LOGIN_HOST || this.currentHost;
    this.protocol = this.loginHost.startsWith('localhost') ? 'http' : 'https';
    this.i18n = this.initI18n(locale);
  }

  initI18n(locale?: LocaleTypes) {
    const locales = path.join(__dirname, '../locales');
    const i18n = new I18n();
    i18n.configure({
      locales: ['en', 'zh'],
      directory: locales,
    });
    i18n.setLocale(locale || LocaleTypes.ZH);
    return i18n;
  }

  async login(): Promise<AuthResponse | null> {
    try {
      const user = await loginUser();
      if (user) {
        const answer = await inquirer.prompt({
          type: 'confirm',
          name: 'confirm',
          message: this.i18n.__('continueLogin'),
          default: true,
        });
        if (!answer.confirm) {
          return null;
        }
        await this.logout();
      }

      return await this.browser();
    } catch (e) {
      logger.error('login failed', e);
    }
    return null;
  }

  async logout() {
    debug(`logout host:${this.currentHost}`);
    await netrc.load();
    const netrcHost = netrc.machines[this.currentHost];
    const username = netrcHost.login ?? '';
    if (username) {
      delete netrc.machines[this.currentHost];
      await netrc.save();
      console.log(this.i18n.__('logoutSuccess', { username }));
      debug(`logout host:${this.currentHost} success`);
    }
  }

  public async browser(): Promise<AuthResponse | null> {
    const appId = vars.oauthAppId();
    if (!appId) {
      console.log(color.error(this.i18n.__('appKeyNotFound')));
      return null;
    }

    let oauthCode: OauthCode;
    try {
      ux.action.start(this.i18n.__('requestCode'));
      const { data } = await api.post<OauthCode>(
        `${this.protocol}://${this.loginHost}/oauth/device/code?client_id=${appId}`,
      );
      oauthCode = data;
      ux.action.stop();
    } catch (e) {
      ux.action.stop();
      console.log(color.error(this.i18n.__('codeError')));
      console.log(color.gray(this.i18n.__('checkProxy')));
      return null;
    }
    if (!oauthCode?.user_code) {
      console.log(color.error(this.i18n.__('codeError')));
      console.log(color.gray(this.i18n.__('checkProxy')));
      return null;
    }

    const deviceUrl = `${this.protocol}://${this.loginHost}${oauthCode.verification_uri}`;
    console.log(color.bold(this.i18n.__('copyCode', { code: oauthCode.user_code })));
    if (os.platform() === 'win32' || os.platform() === 'darwin') {
      try {
        await ux.anykey(this.i18n.__('pressKey', { qCommand: color.bold(color.warn('q')), url: deviceUrl }));
        await open(deviceUrl);
        console.log(this.i18n.__('openManual', { url: deviceUrl }));
      } catch (e) {
        console.log(this.i18n.__('openFailed', { url: deviceUrl }));
        debug('open url failed:');
        debug(JSON.stringify(e));
      }
    } else {
      // 在 webIde 里面尝试打开浏览器
      if (process.env.GFIDE_WORKSPACE) {
        try {
          exec(`code --goto ${deviceUrl} --openExternal`);
        } catch (e) {
          this.showQrCode(deviceUrl);
        }
      } else {
        this.showQrCode(deviceUrl);
      }
    }

    return await this.pollTokenToLogin(appId, oauthCode);
  }

  private showQrCode(url: string) {
    console.log(this.i18n.__('scanQRCode', { url }));
    QRCode.toString(url, { type: 'terminal', small: true }, (err: any, url: string) => {
      if (err) {
        console.log(this.i18n.__('generateQRCodeError'));
        return null;
      }
      console.log(url);
    });
  }

  private async pollTokenToLogin(appId: string, oauthCode: OauthCode): Promise<AuthResponse | null> {
    ux.action.start(this.i18n.__('waitForLogin'));
    const fetchToken = async (retries: number): Promise<AuthToken> => {
      debug(`fetch token: ${retries}`);
      try {
        const { data: authToken } = await api.post(
          `${this.protocol}://${this.loginHost}/oauth/device/token`,
          qs.stringify({
            client_id: appId,
            device_code: oauthCode.device_code,
            grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
          }),
        );
        return authToken;
      } catch (err: any) {
        if (retries > 0 && err.response.status > 500) {
          await new Promise((r) => setTimeout(r, parseInt(oauthCode.interval, 10) * 1000));
          return fetchToken(retries - 1);
        }
        debug(`fetch token error: ${err.response.status}`);
        throw err;
      }
    };
    try {
      const authToken = await fetchToken(
        Math.ceil(parseInt(oauthCode.expires_in, 10) / parseInt(oauthCode.interval, 10)),
      );
      ux.action.stop();
      if (!authToken.access_token) {
        console.log(this.i18n.__('accessTokenError'));
        return null;
      }
      ux.action.start(this.i18n.__('loggingIn'));
      const { data: result } = await api.get(`https://${this.currentHost}/api/v3/user`, {
        headers: {
          Authorization: `Bearer ${authToken.access_token}`,
        },
      });
      ux.action.stop();
      return {
        accessToken: authToken.access_token,
        refreshToken: authToken.refresh_token,
        username: result.username,
      };
    } catch (err: any) {
      ux.action.stop();
      if (err.response?.data) {
        let reason = err.response.data;
        if (reason === 'expired token') {
          reason = this.i18n.__('codeExpired');
        }
        console.log(color.error(this.i18n.__('exitLogin', { error: reason })));
        return null;
      }
      console.log(color.error(this.i18n.__('loginError')));
      return null;
    }
  }
}
