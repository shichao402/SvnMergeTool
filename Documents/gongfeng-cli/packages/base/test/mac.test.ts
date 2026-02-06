import { expect, fancy } from 'fancy-test';
import * as os from 'os';

import getMAC from '../src/mac';

describe('get mac', () => {
  fancy
    .stub(os, 'networkInterfaces', () => {
      return {
        lo0: [
          {
            address: '127.0.0.1',
            netmask: '255.0.0.0',
            family: 'IPv4',
            mac: '00:00:00:00:00:00',
            internal: true,
            cidr: '127.0.0.1/8',
          },
          {
            address: '::1',
            netmask: 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
            family: 'IPv6',
            mac: '00:00:00:00:00:00',
            internal: true,
            cidr: '::1/128',
            scopeid: 0,
          },
          {
            address: 'fe80::1',
            netmask: 'ffff:ffff:ffff:ffff::',
            family: 'IPv6',
            mac: '00:00:00:00:00:00',
            internal: true,
            cidr: 'fe80::1/64',
            scopeid: 1,
          },
        ],
        en1: [
          {
            address: 'fe80::d3:4750:2281:3dcd',
            netmask: 'ffff:ffff:ffff:ffff::',
            family: 'IPv6',
            mac: '14:20:5e:00:90:c8',
            internal: false,
            cidr: 'fe80::d3:4750:2281:3dcd/64',
            scopeid: 7,
          },
          {
            address: '10.89.4.64',
            netmask: '255.255.255.0',
            family: 'IPv4',
            mac: '14:20:5e:00:90:c8',
            internal: false,
            cidr: '10.89.4.64/24',
          },
        ],
        awdl0: [
          {
            address: 'fe80::70a4:27ff:fe0d:d58d',
            netmask: 'ffff:ffff:ffff:ffff::',
            family: 'IPv6',
            mac: '72:a4:27:0d:d5:8d',
            internal: false,
            cidr: 'fe80::70a4:27ff:fe0d:d58d/64',
            scopeid: 12,
          },
        ],
        utun0: [
          {
            address: 'fe80::252e:40c6:fb46:16d9',
            netmask: 'ffff:ffff:ffff:ffff::',
            family: 'IPv6',
            mac: '00:00:00:00:00:00',
            internal: false,
            cidr: 'fe80::252e:40c6:fb46:16d9/64',
            scopeid: 13,
          },
        ],
        utun1: [
          {
            address: '192.168.255.10',
            netmask: '255.255.255.0',
            family: 'IPv4',
            mac: '00:00:00:00:00:00',
            internal: false,
            cidr: '192.168.255.10/24',
          },
        ],
        utun2: [
          {
            address: 'fe80::bceb:bb14:e192:11b4',
            netmask: 'ffff:ffff:ffff:ffff::',
            family: 'IPv6',
            mac: '00:00:00:00:00:00',
            internal: false,
            cidr: 'fe80::bceb:bb14:e192:11b4/64',
            scopeid: 17,
          },
        ],
        utun3: [
          {
            address: 'fe80::a50d:763:a184:8736',
            netmask: 'ffff:ffff:ffff:ffff::',
            family: 'IPv6',
            mac: '00:00:00:00:00:00',
            internal: false,
            cidr: 'fe80::a50d:763:a184:8736/64',
            scopeid: 18,
          },
        ],
        utun4: [
          {
            address: 'fe80::d178:d3c4:fa7d:1eed',
            netmask: 'ffff:ffff:ffff:ffff::',
            family: 'IPv6',
            mac: '00:00:00:00:00:00',
            internal: false,
            cidr: 'fe80::d178:d3c4:fa7d:1eed/64',
            scopeid: 19,
          },
        ],
        utun5: [
          {
            address: 'fe80::a498:733f:7409:70e0',
            netmask: 'ffff:ffff:ffff:ffff::',
            family: 'IPv6',
            mac: '00:00:00:00:00:00',
            internal: false,
            cidr: 'fe80::a498:733f:7409:70e0/64',
            scopeid: 20,
          },
        ],
      };
    })
    .it('get mac success', () => {
      const mac = getMAC();
      expect(mac).to.equal('14:20:5e:00:90:c8');
    });

  fancy
    .stub(os, 'networkInterfaces', () => {
      return '';
    })
    .it('get mac failed', () => {
      expect(getMAC()).to.equal('');
    });
});
