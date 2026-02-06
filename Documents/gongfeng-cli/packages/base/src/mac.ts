import { NetworkInterfaceInfo, networkInterfaces } from 'os';
const zeroRegex = /(?:[0]{1,2}[:-]){5}[0]{1,2}/;

/**
 * 获取机器 MAC 地址
 */
export default function getMAC(): string {
  const list = networkInterfaces();
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  for (const [key, parts] of Object.entries(list)) {
    if (!parts) continue;
    for (const part of parts) {
      if (!zeroRegex.test(part.mac)) {
        return part.mac;
      }
    }
  }
  return '';
}

/**
 * Returns an array of `NetworkInterfaceInfo`s for all host interfaces that
 * have IPv4 addresses from the external private address space,
 * ie. except the loopback (internal) address space (127.x.x.x).
 */
export const getPrivateExternalIPNInfos = (): (NetworkInterfaceInfo | undefined)[] => {
  return Object.values(networkInterfaces())
    .flatMap((infos) => {
      return infos?.filter((i) => !i.internal && i.family === 'IPv4');
    })
    .filter((info) => {
      return info?.address.match(/(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.)/) !== null;
    });
};

/**
 * Returns an array of IPv4 addresses for all host interfaces that
 * have IPv4 addresses from the external private address space,
 * ie. except the loopback (internal) address space (127.x.x.x).
 */
export const getPrivateExternalIPs = (): (string | undefined)[] => {
  return getPrivateExternalIPNInfos().map((i) => i?.address);
};
