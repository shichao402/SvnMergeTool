import * as fs from 'fs-extra';
import Debug from 'debug';

const debug = Debug('gongfeng-base:file');

export function existsSync(f: string): boolean {
  return fs.existsSync(f);
}

export function readdirSync(f: string): string[] {
  debug('readdir', f);
  return fs.readdirSync(f);
}

export function readFileSync(f: string) {
  debug('readFile', f);
  return fs.readFileSync(f);
}

export function readJsonSync(f: string) {
  debug('readJson', f);
  return fs.readJsonSync(f);
}
