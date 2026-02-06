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
    .command(['aicr:diff', '-t testdd', '-s packages/aicr/src/util.ts', '-s packages/aicr/src/commands/aicr/diff.ts'])
    .it('runs hello cmd', (ctx) => {
      expect(ctx.stdout).to.contain('hello friend from oclif!');
    });
});
