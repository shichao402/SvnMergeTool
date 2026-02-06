import { expect, test } from '@oclif/test';
import * as base from '@tencent/gongfeng-cli-base';

describe('auth:whoami', () => {
  test
    .stub(base, 'loginUser', () => {
      return () => {
        return '';
      };
    })
    .stdout()
    .stderr()
    .command(['auth:whoami'])
    .exit(100)
    .it('user not logged in', (ctx) => {
      expect(ctx.stdout).to.contain('Not logged in');
    });

  test
    .stub(base, 'loginUser', () => {
      return () => {
        return 'jack';
      };
    })
    .stdout()
    .command(['auth:whoami'])
    .it('user logged in', (ctx) => {
      expect(ctx.stdout).to.contain('jack');
    });
});
