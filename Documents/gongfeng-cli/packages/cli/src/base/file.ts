import * as FS from 'fs-extra';
import * as path from 'path';
import deps from './deps';
import Debug from 'debug';

const debug = Debug('gongfeng:file');

export function exists(filepath: string): Promise<boolean> {
  return deps.fs.pathExists(filepath);
}

export async function stat(file: string): Promise<FS.Stats> {
  return deps.fs.stat(file);
}

export async function rename(from: string, to: string) {
  debug('rename', from, to);
  return deps.fs.rename(from, to);
}

export async function remove(file: string) {
  if (!(await exists(file))) return;
  debug('remove', file);
  return deps.fs.remove(file);
}

export async function ls(dir: string): Promise<{ path: string; stat: FS.Stats }[]> {
  const files = await deps.fs.readdir(dir);
  const paths = files.map((f) => path.join(dir, f));
  return Promise.all(paths.map((path) => deps.fs.stat(path).then((stat) => ({ path, stat }))));
}

export async function removeEmptyDirs(dir: string) {
  let files;
  try {
    files = await ls(dir);
  } catch (error: any) {
    if (error.code === 'ENOENT') {
      return;
    }
    throw error;
  }
  const dirs = files.filter((f) => f.stat.isDirectory()).map((f) => f.path);
  for (const p of dirs.map(removeEmptyDirs)) {
    await p;
  }
  files = await ls(dir);
  if (files.length === 0) {
    await remove(dir);
  }
}

export async function readJSON(file: string) {
  debug('readJSON', file);
  return deps.fs.readJSON(file);
}

export function readJSONSync(file: string) {
  debug('readJSONSync', file);
  return deps.fs.readJsonSync(file);
}

export async function outputJSON(file: string, data: any, options: FS.WriteOptions = {}) {
  debug('outputJSON', file);
  return deps.fs.outputJson(file, data, { spaces: 2, ...options });
}

export function realpathSync(file: string) {
  return deps.fs.realpathSync(file);
}
