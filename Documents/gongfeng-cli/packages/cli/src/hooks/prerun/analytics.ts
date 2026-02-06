import { Hook } from '@oclif/core';
import Analytics from '../../base/analytics';
import { logger } from '@tencent/gongfeng-cli-base';
import Debug from 'debug';

const debug = Debug('gongfeng:analytics');

export const analytics: Hook.Prerun = async function (options) {
  const analytics = new Analytics(this.config);
  analytics
    .record(options)
    .then(() => debug('report datahub success'))
    .catch((e) => {
      debug('report datahub failed');
      logger.error(JSON.stringify(e));
    });
};
