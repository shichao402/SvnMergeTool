import { expect } from 'chai';

import { vars } from '../src';

const { env } = process;
const customHost = 'customhost';
const devHost = 'dev.git.woa.com';
beforeEach(() => {
  process.env = {};
});
afterEach(() => {
  process.env = env;
});

describe('vars', () => {
  it('sets vars by default', async () => {
    const host = vars.host();
    const apiUrl = vars.apiUrl();
    expect(vars.gongfengEnv).to.equal('pro');
    expect(host).to.equal('git.woa.com');
    expect(apiUrl).to.equal('https://git.woa.com/api/web/v1');
  });

  it('set custom host', async () => {
    process.env.GONGFENG_HOST = customHost;
    const host = vars.host();
    const apiUrl = vars.apiUrl();
    expect(vars.gongfengEnv).to.equal('');
    expect(host).to.equal(customHost);
    expect(apiUrl).to.equal(`https://${customHost}/api/web/v1`);
  });

  it('set dev host', async () => {
    process.env.GONGFENG_HOST = devHost;
    const host = vars.host();
    const apiUrl = vars.apiUrl();
    expect(vars.gongfengEnv).to.equal('dev');
    expect(host).to.equal(devHost);
    expect(apiUrl).to.equal(`https://${devHost}/api/web/v1`);
  });
});
