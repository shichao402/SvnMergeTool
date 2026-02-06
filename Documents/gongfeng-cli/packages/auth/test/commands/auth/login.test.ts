import { expect, test } from '@oclif/test';
import { vars, shell } from '@tencent/gongfeng-cli-base';
import * as inquirer from 'inquirer';

describe('auth:login', () => {
  test
    .stub(vars, 'oauthAppId', () => {
      return '';
    })
    .stdout()
    .command(['auth:login', '--code'])
    .it('appId not found', (ctx) => {
      expect(ctx.stdout).to.contain('oauth app id not found');
    });

  describe('code failed', () => {
    test
      .stub(vars, 'oauthAppId', () => {
        return 'appid12345';
      })
      .stub(vars, 'host', () => {
        return 'git.woa.com';
      })
      .nock('https://git.woa.com/', (api) => {
        api.post('/oauth/device/code?client_id=appid12345').reply(200, {
          user_code: '',
        });
      })
      .stdout()
      .command(['auth:login', '--code'])
      .it('request code failed', (ctx) => {
        expect(ctx.stdout).to.contain('Request code failed');
      });
  });

  describe('code expired', () => {
    test
      .stub(vars, 'oauthAppId', () => {
        return 'appid12345';
      })
      .stub(vars, 'host', () => {
        return 'git.woa.com';
      })
      .nock('https://git.woa.com', (api) => {
        api.post('/oauth/device/code?client_id=appid12345').reply(200, {
          user_code: 'DJLK-WOIM',
          device_code: 'sliokwejlwekjwel',
          expires_in: '60',
          interval: '5',
        });
        api
          .post(
            '/oauth/device/token',
            'client_id=appid12345&device_code=sliokwejlwekjwel&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code',
          )
          .reply(400, 'expired token');
      })
      .stdout()
      .command(['auth:login', '--code'])
      .it('request code expired', (ctx) => {
        expect(ctx.stdout).to.contain('one-time code: DJLK-WOIM');
        expect(ctx.stdout).to.contain('Code has been expired');
      });
  });

  test
    .stub(vars, 'oauthAppId', () => {
      return 'appid12345';
    })
    .stub(vars, 'host', () => {
      return 'git.woa.com';
    })
    .nock('https://git.woa.com', (api) => {
      api.post('/oauth/device/code?client_id=appid12345').reply(200, {
        user_code: 'DJLK-WOIM',
        device_code: 'sliokwejlwekjwel',
        expires_in: '60',
        interval: '5',
      });
      api
        .post(
          '/oauth/device/token',
          'client_id=appid12345&device_code=sliokwejlwekjwel&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code',
        )
        .reply(509);
      api
        .post(
          '/oauth/device/token',
          'client_id=appid12345&device_code=sliokwejlwekjwel&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code',
        )
        .reply(509);
      api
        .post(
          '/oauth/device/token',
          'client_id=appid12345&device_code=sliokwejlwekjwel&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code',
        )
        .reply(200, {
          access_token: 'lowwwwww',
          refresh_token: 'loieeew',
        });
      api.get('/api/v3/user').reply(200, {
        username: 'jack',
      });
    })
    .stdout()
    .command(['auth:login', '--code'])
    .it('code login success', (ctx) => {
      expect(ctx.stdout).to.contain('one-time code: DJLK-WOIM');
      expect(ctx.stdout).to.contain('Logged in as jack');
    });

  test
    .stub(vars, 'oauthAppId', () => {
      return 'appid12345';
    })
    .stub(vars, 'host', () => {
      return 'git.woa.com';
    })
    .stub(shell, 'exec', () => {
      return 'jack2';
    })
    .stub(inquirer, 'prompt', () => {
      return {
        username: 'jack',
      };
    })
    .nock('https://git.woa.com', (api) => {
      api.post('/oauth/device/moa?client_id=appid12345&username=jack').reply(200, {
        user_code: 'DJLK-WOIM',
        device_code: 'sliokwejlwekjwel',
        expires_in: '60',
        interval: '5',
      });
      api
        .post(
          '/oauth/device/token',
          'client_id=appid12345&device_code=sliokwejlwekjwel&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code',
        )
        .reply(509);
      api
        .post(
          '/oauth/device/token',
          'client_id=appid12345&device_code=sliokwejlwekjwel&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code',
        )
        .reply(509);
      api
        .post(
          '/oauth/device/token',
          'client_id=appid12345&device_code=sliokwejlwekjwel&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code',
        )
        .reply(200, {
          access_token: 'lowwwwww',
          refresh_token: 'loieeew',
        });
      api.get('/api/v3/user').reply(200, {
        username: 'jack',
      });
    })
    .stdout()
    .command(['auth:login', '--moa'])
    .it('moa login success', (ctx) => {
      expect(ctx.stdout).to.contain('Logged in as jack');
    });
});
