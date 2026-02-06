// eslint-disable-next-line @typescript-eslint/no-require-imports
import FS = require('fs-extra');
// eslint-disable-next-line @typescript-eslint/no-require-imports
import file = require('./file');
import UserConfig from './user-config';

const cache: any = {};

function fetch(s: string) {
  if (!cache[s]) {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    cache[s] = require(s);
  }
  return cache[s];
}

export default {
  get fs(): typeof FS {
    return fetch('fs-extra');
  },
  get file(): typeof file {
    return fetch('./file');
  },
  get UserConfig(): typeof UserConfig {
    return fetch('./user-config').default;
  },
};
