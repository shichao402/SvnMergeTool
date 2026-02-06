import { Interfaces, Command } from '@oclif/core';
import deps from './deps';
import netrc from 'netrc-parser';
import Debug from 'debug';
import { report, replaceBeaconSymbol, git, loginUser } from '@tencent/gongfeng-cli-base';

const debug = Debug('gongfeng:analytics');

export interface RecordOptions {
  Command: Command.Class;
  argv: string[];
  config: Interfaces.Config;
}

export default class Analytics {
  config: Interfaces.Config;
  userConfig!: typeof deps.UserConfig.prototype;

  constructor(config: Interfaces.Config) {
    this.config = config;
  }

  async record(options: RecordOptions) {
    await this.init();
    const { plugin } = options.Command;
    let transformPlugin = null;
    if (plugin) {
      // eslint-disable-next-line @typescript-eslint/consistent-type-assertions
      transformPlugin = <Interfaces.Plugin>(<any>plugin);
    }
    if (!plugin) {
      debug('no plugin found for analytics');
      return;
    }
    if (this.userConfig.skipAnalytics) {
      return;
    }

    let projectPath = '';
    try {
      projectPath = (await git.projectPathFromRemote(process.cwd())) || '';
    } catch (e) {}

    const username = (await loginUser()) || 'anonymous';
    const analyticsData = {
      cli: replaceBeaconSymbol(this.config.name),
      command: replaceBeaconSymbol(options.Command.id),
      version: replaceBeaconSymbol(this.config.version),
      plugin: replaceBeaconSymbol(transformPlugin?.name || ''),
      plugin_version: replaceBeaconSymbol(transformPlugin?.version || ''),
      os: replaceBeaconSymbol(this.config.platform),
      shell: replaceBeaconSymbol(this.config.shell),
      language: 'node',
      install_id: replaceBeaconSymbol(this.userConfig.install),
      username: replaceBeaconSymbol(username),
      project_path: replaceBeaconSymbol(projectPath),
    };
    await report('cli_show', analyticsData);
  }

  private async init() {
    await netrc.load();
    this.userConfig = new deps.UserConfig(this.config);
    await this.userConfig.init();
  }
}
