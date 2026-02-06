import { expect, test } from '@oclif/test';

describe('mr', () => {
  test
    .stdout()
    .command(['mr', 'friend', '--from=oclif'])
    .it('runs mr cmd', (ctx) => {
      expect(ctx.stdout).to.contain('mr friend from oclif!');
    });
});
