import { ux } from '@oclif/core';
import * as qq from 'qqjs';
import * as util from 'util';

// eslint-disable-next-line @typescript-eslint/no-require-imports
export const debug = require('debug')('oclif');
// eslint-disable-next-line @typescript-eslint/no-require-imports
debug.new = (name: string) => require('debug')(`oclif:${name}`);

export function log(format: string, ...args: any[]): void {
  args = args.map((arg: any) => qq.prettifyPaths(arg));
  debug.enabled ? debug(format, ...args) : ux.log(`oclif: ${util.format(format, ...args)}`);
}
