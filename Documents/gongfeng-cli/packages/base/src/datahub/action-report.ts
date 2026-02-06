import { Command } from '@oclif/core';
import report, { replaceBeaconSymbol } from '.';
import { loginUser } from '../pre-auth';

export default class ActionReport {
  command: Command;

  constructor(command: Command) {
    this.command = command;
  }

  public async report(actionType: string, actionValue?: string) {
    const { config, id } = this.command;
    const username = (await loginUser()) || 'anonymous';
    const analyticsData = {
      action_type: replaceBeaconSymbol(actionType),
      action_value: replaceBeaconSymbol(actionValue),
      command: replaceBeaconSymbol(id),
      username: replaceBeaconSymbol(username),
      cli: replaceBeaconSymbol(config.name),
      version: replaceBeaconSymbol(config.version),
      os: replaceBeaconSymbol(config.platform),
      shell: replaceBeaconSymbol(config.shell),
    };
    await report('cli_action', analyticsData);
  }
}
