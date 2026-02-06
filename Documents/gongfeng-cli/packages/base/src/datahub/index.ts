import { vars } from '../vars';
import axios from 'axios';
import getMAC from '../mac';
import { v4 } from 'uuid';
import * as console from 'console';
import logger from '../logger';
import { initSentry } from '../sentry';
import * as Sentry from '@sentry/node';

export interface BeaconEventParam {
  [index: string]: string | number;
}

export function replaceBeaconSymbol(value: any): any {
  if (typeof value !== 'string') {
    return value;
  }
  try {
    return value
      .replace(new RegExp('\\|', 'g'), '%7C')
      .replace(new RegExp('&', 'g'), '%26')
      .replace(new RegExp('=', 'g'), '%3D')
      .replace(new RegExp('\\+', 'g'), '%2B');
  } catch (e) {
    console.log(e);
    return '';
  }
}

const instance = axios.create({
  timeout: 3000,
  headers: { 'Content-Type': 'application/json;charset=UTF-8' },
});

/**
 * 上报数据到灯塔
 * @param eventName 事件名称
 * @param data 时间信息
 */
async function report(eventName: string, data: BeaconEventParam) {
  if (!vars.dataHubKey()) {
    return;
  }
  await initSentry();
  const now = new Date().getTime();
  const mac = getMAC() || v4();
  const datahubData = {
    appVersion: '2.11.1',
    sdkId: 'js',
    sdkVersion: '4.3.4-web',
    mainAppKey: vars.dataHubKey(),
    platformId: 3,
    common: {
      A2: mac,
    },
    events: [
      {
        eventCode: eventName,
        eventTime: `${now}`,
        mapValue: data,
      },
    ],
  };
  try {
    const { data } = await instance.post('https://otheve.beacon.qq.com/analytics/v2_upload', datahubData);
    return data;
  } catch (e) {
    Sentry.setExtra('datahub', 'report failed');
    Sentry.captureException(e);
    logger.error('datahub report failed', e);
  }
}

export default report;
