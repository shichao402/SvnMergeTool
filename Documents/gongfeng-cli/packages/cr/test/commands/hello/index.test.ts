import { expect, test } from '@oclif/test';

describe('hello', () => {
  //process.env.GONGFENG_HOST= 'dev.git.woa.com';
  test
    .stdout()
    .command(['cr:create', 'D:\\svnprojects\\trunk', '-t test', '-d desc'])
    .it('runs hello cmd', (ctx) => {
      expect(ctx.stdout).to.contain('hello friend from oclif!');
    });
});
