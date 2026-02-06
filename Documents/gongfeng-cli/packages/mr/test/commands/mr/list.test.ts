import { expect, test } from '@oclif/test';
import * as base from '@tencent/gongfeng-cli-base';
import { setupEmptyDirectory, setupFixtureRepository } from '../../helpers/repositories';
import { git } from '@tencent/gongfeng-cli-base';

const { file } = base;

describe('mr list', () => {
  describe('check login', () => {
    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return false;
        };
      })
      .stdout()
      .command(['mr list'])
      .exit(0)
      .it('exit when not authed', ({ stdout }) => {
        expect(stdout).to.contain('使用工蜂CLI前，请先执行"gf auth login" (别名:  "gf login")登录工蜂CLI!');
      });
  });

  describe('with non git directory', () => {
    let repoPath: string;
    beforeEach(() => {
      repoPath = setupEmptyDirectory();
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
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .stdout()
      .command(['mr list'])
      .exit(0)
      .it('exit when remote not found', (ctx) => {
        expect(ctx.stdout).to.contain('Current project remote not found!');
      });
  });

  describe('with merge requests', () => {
    let repoPath: string;
    beforeEach(async () => {
      repoPath = await setupFixtureRepository('test-repo');
      await git.addRemote(repoPath, 'origin', 'https://git.woa.com/code/cli');
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
        return 'git.woa.com';
      })
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .nock('https://git.woa.com', (api) => {
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        api
          .get('/api/web/v1/projects/1000/merge_requests?state=opened&perPage=20&sort=created_desc')
          .reply(200, undefined);
      })
      .stdout()
      .command(['mr list'])
      .exit(0)
      .it('exit when no merge requests exist', (ctx) => {
        expect(ctx.stdout).to.contain('No merge requests found in code/cli');
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
        return 'git.woa.com';
      })
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .nock('https://git.woa.com', (api) => {
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        api.get('/api/web/v1/projects/1000/merge_requests?state=opened&perPage=20&sort=created_desc').reply(200, [
          {
            mergeRequest: {
              iid: 1,
              author: {
                username: 'rhainliu',
              },
              titleRaw: 'update file title1',
            },
            noteCount: 0,
            commentCount: 0,
            titleHtml: '更新文件 README.md',
          },
          {
            mergeRequest: {
              iid: 2,
              author: {
                username: 'rhainliu',
              },
              titleRaw: 'update file title2',
            },
          },
        ]);
      })
      .stdout()
      .command(['mr list'])
      .it('current project merge requests exist', (ctx) => {
        expect(ctx.stdout).to.contain('update file title1');
        expect(ctx.stdout).to.contain('update file title2');
        expect(ctx.stdout).to.contain('1');
        expect(ctx.stdout).to.contain('2');
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
        return 'git.woa.com';
      })
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .nock('https://git.woa.com', (api) => {
        api.get('/api/web/v1/projects/gongfeng%2Fcli').reply(200, { id: 10712436 });
        api.get('/api/web/v1/projects/10712436/merge_requests?state=opened&perPage=20&sort=created_desc').reply(200, [
          {
            mergeRequest: {
              iid: 1,
              author: {
                username: 'rhainliu',
              },
              titleRaw: 'update file title1',
            },
            noteCount: 0,
            commentCount: 0,
            titleHtml: '更新文件 README.md',
          },
          {
            mergeRequest: {
              iid: 2,
              author: {
                username: 'rhainliu',
              },
              titleRaw: 'update file title2',
            },
          },
        ]);
      })
      .stdout()
      .command(['mr list', '-R gongfeng/cli'])
      .it('fork project merge requests exist', (ctx) => {
        expect(ctx.stdout).to.contain('update file title1');
        expect(ctx.stdout).to.contain('update file title2');
        expect(ctx.stdout).to.contain('1');
        expect(ctx.stdout).to.contain('2');
      });
  });
});
