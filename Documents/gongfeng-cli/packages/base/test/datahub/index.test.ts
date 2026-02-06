import { replaceBeaconSymbol, report, vars } from '../../src';
import { expect } from 'chai';
import * as nock from 'nock';
import { fancy } from 'fancy-test';

describe('datahub', () => {
  it('replaceBeaconSymbol', () => {
    const symbol1 = 'aaabbb';
    const symbol2 = 'aaa|bbb';
    const symbol2Replaced = 'aaa%7Cbbb';
    const symbol3 = 'aaa&bbb';
    const symbol3Replaced = 'aaa%26bbb';
    const symbol4 = 'aaa=bbb';
    const symbol4Replaced = 'aaa%3Dbbb';
    const symbol5 = 'aaa+bbb+ccc+ddd';
    const symbol5Replaced = 'aaa%2Bbbb%2Bccc%2Bddd';
    expect(replaceBeaconSymbol(symbol1)).to.equal(symbol1);
    expect(replaceBeaconSymbol(symbol2)).to.equal(symbol2Replaced);
    expect(replaceBeaconSymbol(symbol3)).to.equal(symbol3Replaced);
    expect(replaceBeaconSymbol(symbol4)).to.equal(symbol4Replaced);
    expect(replaceBeaconSymbol(symbol5)).to.equal(symbol5Replaced);
  });

  fancy
    .stub(vars, 'dataHubKey', () => {
      return 'JKOKMLPI2332';
    })
    .it('report datahub', async () => {
      const response = {
        result: '200',
        srcGatewayIp: '0.0.0.0',
        serverTime: '1652681799053',
        msg: 'success',
      };
      nock('https://otheve.beacon.qq.com').post('/analytics/v2_upload').reply(200, response);

      const data = await report('cli-show', {
        cli: '@tencent/gongfeng-cli',
        command: 'gf',
      });
      expect(data).to.deep.equal(response);
    });
});
