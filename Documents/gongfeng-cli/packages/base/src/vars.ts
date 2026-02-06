import { Flags, ux } from '@oclif/core';
import * as dotenv from 'dotenv';
import { resolve } from 'path';
import { Git } from './git-shell';

const LOCAL_HOST = '127.0.0.1';
const DEV_HOST = 'dev.git.woa.com';
const TEST_HOST = 'test.git.woa.com';
const STAGING_HOST = 'staging.git.woa.com';
const PRO_HOST = 'git.woa.com';

const env = getEnvFromHost();
if (env) {
  dotenv.config({ path: resolve(__dirname, `../env/.${env}.env`), debug: false, override: true });
}

function getEnvFromHost() {
  const gongfengHost = process.env.GONGFENG_HOST;
  if (gongfengHost === LOCAL_HOST) {
    return 'local';
  }
  if (gongfengHost === DEV_HOST) {
    return 'dev';
  }
  if (gongfengHost === TEST_HOST) {
    return 'test';
  }
  if (gongfengHost === STAGING_HOST) {
    return 'staging';
  }
  if (gongfengHost === PRO_HOST) {
    return 'pro';
  }
  // 设置了gongfeng host 但不是指定名单的，不加载环境变量
  if (gongfengHost) {
    return '';
  }
  return 'pro';
}

/**
 * 系统变量
 */
export class Vars {
  hadInit = false;
  gitHost = '';
  timeFormatter = 'YYYY-MM-DD HH:mm:ss';

  init() {
    const git = new Git();
    try {
      const remote = git.remoteUrl();
      if (remote) {
        const url = new URL(remote);
        this.gitHost = url.host;
      }
    } catch (e) {}
    this.hadInit = true;
  }

  get gongfengEnv(): string {
    return getEnvFromHost();
  }

  host(): string {
    if (!this.hadInit) {
      this.init();
    }
    // 优先使用通过环境变量设置的 GONGFENG_HOST
    if (process.env.GONGFENG_HOST) {
      return process.env.GONGFENG_HOST;
    }
    // 没有设置环境变量的 GONGFENG_HOST 时，优先从本地项目获取
    if (this.gitHost) {
      return this.gitHost;
    }
    return PRO_HOST;
  }

  dataHubKey(): string {
    if (!this.hadInit) {
      this.init();
    }
    return process.env.DATA_HUB_KEY || '';
  }

  dsn(): string {
    if (!this.hadInit) {
      this.init();
    }
    return process.env.DSN || '';
  }

  apiUrl(): string {
    const host = this.host();
    if (host.indexOf('localhost') >= 0) {
      return `http://${host}/api/web/v1`;
    }
    return `https://${host}/api/web/v1`;
  }

  copilotApiUrl(): string {
    const host = this.host();
    if (host.indexOf('localhost') >= 0) {
      return `http://${host}/api/copilot/v3`;
    }
    return `https://${host}/api/copilot/v3`;
  }

  oauthAppId(): string {
    if (!this.hadInit) {
      this.init();
    }
    return process.env.OAUTH_APP_ID || '';
  }

  // 将表格相关的 flags 描述翻译为中文
  tableFlags(): typeof ux.table.Flags {
    return {
      extended: Flags.boolean({
        description: '显示更多的列',
        required: false,
        helpGroup: '公共参数',
      }),
      columns: Flags.string({
        description: '仅显示指定列（多个值之间用,分隔）',
        required: false,
        helpGroup: '公共参数',
      }),
      filter: Flags.string({
        description: '对指定列进行过滤，例如: --filter="标题=wip"',
        required: false,
        helpGroup: '公共参数',
      }),
      'no-header': Flags.boolean({
        description: '隐藏列表的header',
        required: false,
        helpGroup: '公共参数',
      }),
      'no-truncate': Flags.boolean({
        description: '不截断输出',
        required: false,
        helpGroup: '公共参数',
      }),
      output: Flags.string({
        description: '以其他格式输出，可选值为“csv|json|yaml”',
        required: false,
        helpGroup: '公共参数',
      }),
      sort: Flags.string({
        description: '通过指定字段名进行排序（降序在字段名前加上“-”）',
        required: false,
        helpGroup: '公共参数',
      }),
      csv: Flags.boolean({
        description: '以csv格式输出（“--output=csv” 的别名）',
        required: false,
        helpGroup: '公共参数',
      }),
    };
  }
}

export const vars = new Vars();
