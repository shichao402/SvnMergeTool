import * as path from 'path';
import { Interfaces } from '@oclif/core';
import Debug from 'debug';
import deps from './deps';
import { v4 } from 'uuid';
import { CONFIG_FILE } from '@tencent/gongfeng-cli-base';

export interface GongFengConfig {
  schema: 1;
  install?: string;
  skipAnalytics?: boolean;
}

export default class UserConfig {
  private needsSave = false;
  private body!: GongFengConfig;
  private mtime?: number;
  private saving?: Promise<void>;
  private initPromise!: Promise<void>;

  constructor(private readonly config: Interfaces.Config) {}

  public async init() {
    await this.saving;
    if (this.initPromise) {
      return this.initPromise;
    }
    this.initPromise = (async () => {
      this.debug('init');
      this.body = (await this.read()) || { schema: 1 };

      if (!this.body.schema) {
        this.body.schema = 1;
        this.needsSave = true;
      } else if (this.body.schema !== 1) {
        this.body = { schema: 1 };
      }
      if (!this.install) {
        this.genInstall();
      }
      if (typeof this.body.skipAnalytics !== 'boolean') {
        this.body.skipAnalytics = false;
        this.needsSave = true;
      }
      if (this.needsSave) {
        await this.save();
      }
    })();

    return this.initPromise;
  }

  public get install(): string {
    return this.body.install || '';
  }

  public set install(install: string) {
    this.body.install = install;
    this.needsSave = true;
  }

  public get skipAnalytics() {
    if (this.config.scopedEnvVar('SKIP_ANALYTICS') === '1') {
      return true;
    }
    if (typeof this.body.skipAnalytics !== 'boolean') {
      this.body.skipAnalytics = false;
      this.needsSave = true;
    }
    return this.body.skipAnalytics;
  }

  private get debug() {
    return Debug('gongfeng:user_config');
  }

  private get file() {
    return path.join(this.config.dataDir, CONFIG_FILE);
  }

  private async getLastUpdated(): Promise<number | undefined> {
    try {
      const stat = await deps.file.stat(this.file);
      return stat.mtime.getTime();
    } catch (error: any) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
    }
  }

  private async read(): Promise<GongFengConfig | undefined> {
    try {
      this.mtime = await this.getLastUpdated();
      return await deps.file.readJSON(this.file);
    } catch (error: any) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
      this.debug('not found');
    }
  }

  private async canWrite() {
    if (!this.mtime) return true;
    return (await this.getLastUpdated()) === this.mtime;
  }

  private async save(): Promise<void> {
    if (!this.needsSave) {
      return;
    }
    this.needsSave = false;
    this.saving = (async () => {
      this.debug('saving');
      if (!(await this.canWrite())) {
        throw new Error('file modified, cannot save');
      }
      await deps.file.outputJSON(this.file, this.body);
    })();
  }

  private genInstall(): string {
    this.install = v4();
    return this.install;
  }
}
