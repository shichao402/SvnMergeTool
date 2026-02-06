import { expect, test } from '@oclif/test';

describe('hello world', () => {
  test
    .stdout()
    .command(['aicr:commit', 'ef375e70', '-t wsss', '-s packages/aicr/src/commands/aicr/commit.ts', '-s packages/aicr/src/commands/aicr/diff.ts'])
    .it('runs hello world cmd', (ctx) => {
      expect(ctx.stdout).to.contain('hello world!');
    });
});
