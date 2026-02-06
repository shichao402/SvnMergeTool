// eslint-disable-next-line @typescript-eslint/no-unused-vars
import * as typings from './types/index.d';
import { Command } from '@oclif/core';
import * as path from 'path';
import * as i18n from 'i18n';
import {
  CONFIG_FILE,
  file,
  checkAuth,
  color,
  authToken,
  vars,
  authHeaders,
  getTraceId,
} from '@tencent/gongfeng-cli-base';
import 'reflect-metadata';
import axios, { AxiosError, AxiosInstance, AxiosResponse } from 'axios';
import * as Sentry from '@sentry/node';
import Debug from 'debug';

const debug = Debug('gongfeng-auth:base');

export default abstract class BaseCommand extends Command {
  api!: AxiosInstance;

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
    this.initI18n();
    await this.initApi();
  }

  initI18n() {
    let locale = 'zh';
    const configFile = path.join(this.config.dataDir, CONFIG_FILE);
    if (file.existsSync(configFile)) {
      const config = file.readJsonSync(configFile);
      locale = config.locale || 'zh';
    }
    let locales = path.join(__dirname, 'locales');
    if (process.env.NODE_ENV === 'development') {
      locale = 'en';
      locales = path.resolve(__dirname, '../locales');
    }
    i18n.configure({
      locales: ['en', 'zh'],
      directory: locales,
      register: global,
    });
    i18n.setLocale(locale);
  }

  async initApi() {
    const token = await authToken();
    const baseApi = vars.apiUrl();
    if (token) {
      this.api = axios.create({
        baseURL: baseApi,
        timeout: 20000,
        headers: await authHeaders(),
      });
    } else {
      this.api = axios.create({
        baseURL: baseApi,
        timeout: 20000,
        headers: { 'User-Agent': 'GFCLI' },
      });
    }
    this.api.interceptors.response.use(
      (response: AxiosResponse) => response,
      (error: AxiosError) => {
        Sentry.captureException(error);
        if (getTraceId(error)) {
          debug(`traceId: ${getTraceId(error)}`);
        }
        return Promise.reject(error);
      },
    );
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
