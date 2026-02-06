import { expect, test } from '@oclif/test';
import * as base from '@tencent/gongfeng-cli-base';

const { file } = base;

describe('mr', () => {
  let repoPath: string;
  beforeEach(async () => {
    repoPath = '/Users/rhain/test/rhaincli/cli';
  });
  test
    .stub(base, 'checkAuth', () => {
      return () => {
        return true;
      };
    })
    .stub(file, 'readJsonSync', () => {
      return {};
    })
    .stub(base.vars, 'host', () => {
      return 'dev.git.woa.com';
    })
    .stub(process, 'cwd', () => {
      return repoPath;
    })
    .stdout()
    .command(['mr create', '-T master'])
    .it('runs mr create', (ctx) => {
      expect(ctx.stdout).to.contain('mr friend from oclif!');
    });
});
