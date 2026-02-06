import { expect, test } from '@oclif/test';
import * as base from '@tencent/gongfeng-cli-base';
import { setupEmptyDirectory, setupFixtureRepository } from '../../helpers/repositories';
import { git } from '@tencent/gongfeng-cli-base';

const { file } = base;

describe('mr mine', () => {
  describe('check login', () => {
    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return false;
        };
      })
      .stdout()
      .command(['mr mine'])
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
      .command(['mr mine'])
      .exit(0)
      .it('exit when remote not found', (ctx) => {
        expect(ctx.stdout).to.contain('Current project remote not found!');
      });
  });

  describe('get mine merge requests', () => {
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
      .stub(base, 'loginUser', () => {
        return () => {
          return 'zhangsan';
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
        api.post('/api/web/v1/users', 'usernames=zhangsan').reply(200, [
          {
            id: 66666,
            username: 'zhangsan',
          },
        ]);
        api.get('/api/web/v1/projects/1000/merge_requests?reviewerId=66666&sort=created_desc').reply(200, [
          {
            mergeRequest: {
              iid: 1,
              author: {
                username: 'zhangsan',
              },
              titleRaw: 'reviewer title1',
            },
            noteCount: 0,
            commentCount: 0,
          },
          {
            mergeRequest: {
              iid: 2,
              author: {
                username: 'zhangsan',
              },
              titleRaw: 'reviewer title2',
            },
          },
        ]);
        api.get('/api/web/v1/projects/1000/merge_requests?authorId=66666&sort=created_desc').reply(200, [
          {
            mergeRequest: {
              iid: 1,
              author: {
                username: 'zhangsan',
              },
              titleRaw: 'author title1',
            },
            noteCount: 0,
            commentCount: 0,
          },
          {
            mergeRequest: {
              iid: 2,
              author: {
                username: 'zhangsan',
              },
              titleRaw: 'author title2',
            },
          },
        ]);
        api
          .get(
            '/api/web/v1/projects/1000/code_review/?authorId=66666&reviewerId=66666&assigneeId=66666&type=web_ready_to_merge&order=readyToMergeAt',
          )
          .reply(200, [
            {
              title: 'ready to merge title2',
              state: 'empty',
              fullName: 'rhainliu/cli',
              fullPath: 'rhainliu/cli',
              sourceFullName: 'rhainliu/cli',
              sourceFullPath: 'rhainliu/cli',
              noteCount: 0,
              diffStartCommitSha: 'd00f266e1b4abddfcbf373692474ab71a8484dee',
              author: { id: 202775, username: 'v_xinphou' },
              iid: 6,
              id: 77817,
              fileCount: 1,
              reviewers: [],
              commitChecks: [],
            },
            {
              title: 'ready to merge title1',
              state: 'empty',
              fullName: 'rhainliu/cli',
              fullPath: 'rhainliu/cli',
              sourceFullName: 'rhainliu/cli',
              sourceFullPath: 'rhainliu/cli',
              noteCount: 0,
              diffStartCommitSha: '43dc55fc835a02261c8de3079be7fb41f0fa16d7',
              author: {
                id: 70664,
                username: 'zhangsan',
              },
              iid: 4,
              id: 77815,
              fileCount: 1,
              reviewers: [],
              commitChecks: [],
            },
          ]);
      })
      .stdout()
      .command(['mr mine'])
      .it('current project merge requests exist', (ctx) => {
        expect(ctx.stdout).to.contain('reviewer title1');
        expect(ctx.stdout).to.contain('reviewer title2');
        expect(ctx.stdout).to.contain('author title1');
        expect(ctx.stdout).to.contain('author title2');
        expect(ctx.stdout).to.contain('ready to merge title2');
        expect(ctx.stdout).to.contain('ready to merge title1');
      });

    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return true;
        };
      })
      .stub(base, 'loginUser', () => {
        return () => {
          return 'zhangsan';
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
        api.get('/api/web/v1/projects/gongfeng%2Fcli').reply(200, { id: 2000 });
        api.post('/api/web/v1/users', 'usernames=zhangsan').reply(200, [
          {
            id: 66666,
            username: 'zhangsan',
          },
        ]);
        api.get('/api/web/v1/projects/2000/merge_requests?reviewerId=66666&sort=created_desc').reply(200, [
          {
            mergeRequest: {
              iid: 1,
              author: {
                username: 'zhangsan',
              },
              titleRaw: 'reviewer title1',
            },
            noteCount: 0,
            commentCount: 0,
          },
          {
            mergeRequest: {
              iid: 2,
              author: {
                username: 'zhangsan',
              },
              titleRaw: 'reviewer title2',
            },
          },
        ]);
        api.get('/api/web/v1/projects/2000/merge_requests?authorId=66666&sort=created_desc').reply(200, [
          {
            mergeRequest: {
              iid: 1,
              author: {
                username: 'zhangsan',
              },
              titleRaw: 'author title1',
            },
            noteCount: 0,
            commentCount: 0,
          },
          {
            mergeRequest: {
              iid: 2,
              author: {
                username: 'zhangsan',
              },
              titleRaw: 'author title2',
            },
          },
        ]);
        api
          .get(
            '/api/web/v1/projects/2000/code_review/?authorId=66666&reviewerId=66666&assigneeId=66666&type=web_ready_to_merge&order=readyToMergeAt',
          )
          .reply(200, [
            {
              title: 'ready to merge title2',
              state: 'empty',
              fullName: 'rhainliu/cli',
              fullPath: 'rhainliu/cli',
              sourceFullName: 'rhainliu/cli',
              sourceFullPath: 'rhainliu/cli',
              noteCount: 0,
              diffStartCommitSha: 'd00f266e1b4abddfcbf373692474ab71a8484dee',
              author: { id: 202775, username: 'v_xinphou' },
              iid: 6,
              id: 77817,
              fileCount: 1,
              reviewers: [],
              commitChecks: [],
            },
            {
              title: 'ready to merge title1',
              state: 'empty',
              fullName: 'rhainliu/cli',
              fullPath: 'rhainliu/cli',
              sourceFullName: 'rhainliu/cli',
              sourceFullPath: 'rhainliu/cli',
              noteCount: 0,
              diffStartCommitSha: '43dc55fc835a02261c8de3079be7fb41f0fa16d7',
              author: {
                id: 70664,
                username: 'zhangsan',
              },
              iid: 4,
              id: 77815,
              fileCount: 1,
              reviewers: [],
              commitChecks: [],
            },
          ]);
      })
      .stdout()
      .command(['mr mine', '-R gongfeng/cli'])
      .it('fork project merge requests exist', (ctx) => {
        expect(ctx.stdout).to.contain('reviewer title1');
        expect(ctx.stdout).to.contain('reviewer title2');
        expect(ctx.stdout).to.contain('author title1');
        expect(ctx.stdout).to.contain('author title2');
        expect(ctx.stdout).to.contain('ready to merge title2');
        expect(ctx.stdout).to.contain('ready to merge title1');
      });
  });
});
