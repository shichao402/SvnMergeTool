import { expect, test } from '@oclif/test';
import * as base from '@tencent/gongfeng-cli-base';

describe('hello', () => {
  test
    .stub(base, 'checkAuth', () => {
      return () => {
        return true;
      };
    })
    .stdout()
    .command(['repo clone', 'code/cli', '--from=oclif'])
    .it('runs hello cmd', (ctx) => {
      expect(ctx.stdout).to.contain('hello friend from oclif!');
    });
});
