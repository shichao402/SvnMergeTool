import netrc from 'netrc-parser';
import getMAC, { getPrivateExternalIPs } from './mac';
import { vars } from './vars';
import * as Sentry from '@sentry/node';

let isInit = false;

export async function initSentry() {
  if (isInit) {
    return;
  }
  const loginHost = vars.host();
  const dsn = vars.dsn();
  Sentry.init({
    dsn,
    tracesSampleRate: 0.5,
  });
  await netrc.load();
  const previousEntry = netrc.machines[loginHost];
  const ips = getPrivateExternalIPs();
  Sentry.configureScope(async (scope) => {
    if (previousEntry?.login) {
      // 如果已经登陆了，就设置用户名信息
      scope.setUser({
        username: previousEntry.login,
      });
    }
    if (getMAC()) {
      // 如果有mac地址信息，就设置mac地址信息
      scope.setExtra('mac_address', getMAC());
    }
    if (ips?.length) {
      scope.setExtra('ip', ips[0]);
    }
  });
  isInit = true;
}
