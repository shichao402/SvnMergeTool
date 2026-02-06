import { expect, test } from '@oclif/test';
import * as base from '@tencent/gongfeng-cli-base';
import { setupEmptyDirectory, setupFixtureRepository } from '../../helpers/repositories';

const { file, git } = base;

describe('mr close', () => {
  describe('check login', () => {
    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return false;
        };
      })
      .stdout()
      .command(['mr edit', '1'])
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
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .stub(file, 'readJsonSync', () => {
        return {};
      })
      .stdout()
      .command(['mr edit', '1'])
      .exit(0)
      .it('exit when remote not found', (ctx) => {
        expect(ctx.stdout).to.contain('Current project remote not found!');
      });
  });

  describe('with remote not found', () => {
    let repoPath: string;
    beforeEach(async () => {
      repoPath = await setupFixtureRepository('test-repo');
    });
    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return true;
        };
      })
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .stub(file, 'readJsonSync', () => {
        return {};
      })
      .stdout()
      .command(['mr edit', '1'])
      .exit(0)
      .it('exit when remote not found', (ctx) => {
        expect(ctx.stdout).to.contain('Current project remote not found!');
      });
  });

  describe('with project not found', () => {
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
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, undefined);
      })
      .stdout()
      .command(['mr edit', '1'])
      .exit(0)
      .it('exit when project not found', (ctx) => {
        expect(ctx.stdout).to.contain('Project not found on GongFeng');
      });
  });

  describe('with merge request not found', () => {
    let repoPath: string;
    const mrIid = 1;
    const branch = 'dev';
    beforeEach(async () => {
      repoPath = await setupFixtureRepository('test-repo');
      await git.addRemote(repoPath, 'origin', 'https://git.woa.com/code/cli');
    });
    // 通过 mr iid 关闭 mr
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
        // 模拟获取项目信息，命令中仅使用到了 project.id
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        // 模拟根据 mr iid 获取 mr 信息
        api.get(`/api/web/v1/projects/1000/merge_requests/${mrIid}`).reply(200, undefined);
      })
      .stdout()
      .command(['mr close', '1'])
      .exit(0)
      .it('mr not found by iid', (ctx) => {
        expect(ctx.stdout).to.contain(`Merge request !${mrIid} not found!`);
      });

    // 通过 源分支名 关闭 mr
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
        // 模拟获取项目信息，命令中仅使用到了 project.id
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        // 模拟根据 目标分支 获取该分支第一条 mr
        api
          .get(`/api/web/v1/projects/1000/merge_requests?perPage=1&sourceBranch=${branch}&sort=created_desc`)
          .reply(200, []);
      })
      .stdout()
      .command(['mr close', 'dev'])
      .exit(0)
      .it('mr not found for branch', (ctx) => {
        expect(ctx.stdout).to.contain(`No merge requests found for branch "${branch}"`);
      });
  });

  describe('with merge request', () => {
    let repoPath: string;
    const mockMergeRequest = {
      iid: 1,
      state: 'opened',
      titleRaw: 'a mocked merge request',
    };
    const mockReview = {
      iid: 1,
    };
    const branch = 'dev';
    beforeEach(async () => {
      repoPath = await setupFixtureRepository('test-repo');
      await git.addRemote(repoPath, 'origin', 'https://git.woa.com/code/cli');
    });
    // 通过 mr iid 关闭 mr (state === closed)
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
        // 模拟获取项目信息，命令中仅使用到了 project.id
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        // 模拟根据 mr iid 获取 mr 信息
        api.get(`/api/web/v1/projects/1000/merge_requests/${mockMergeRequest.iid}`).reply(200, {
          mergeRequest: { ...mockMergeRequest, state: 'closed' },
        });
      })
      .stdout()
      .command(['mr close', `${mockMergeRequest.iid}`])
      .exit(0)
      .it('mr is already closed', (ctx) => {
        expect(ctx.stdout).to.contain(
          `Merge request !${mockMergeRequest.iid} (${mockMergeRequest.titleRaw}) is already closed`,
        );
      });

    // 通过 mr iid 关闭 mr (state === merged)
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
        // 模拟获取项目信息，命令中仅使用到了 project.id
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        // 模拟根据 mr iid 获取 mr 信息
        api.get(`/api/web/v1/projects/1000/merge_requests/${mockMergeRequest.iid}`).reply(200, {
          mergeRequest: { ...mockMergeRequest, state: 'merged' },
        });
      })
      .stdout()
      .command(['mr close', `${mockMergeRequest.iid}`])
      .exit(0)
      .it('mr is already merged', (ctx) => {
        expect(ctx.stdout).to.contain(
          `Merge request !${mockMergeRequest.iid} (${mockMergeRequest.titleRaw}) can't be closed because it was already merged`,
        );
      });

    // 通过 mr iid 关闭 mr (state === locked)
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
        // 模拟获取项目信息，命令中仅使用到了 project.id
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        // 模拟根据 mr iid 获取 mr 信息
        api.get(`/api/web/v1/projects/1000/merge_requests/${mockMergeRequest.iid}`).reply(200, {
          mergeRequest: { ...mockMergeRequest, state: 'locked' },
        });
      })
      .stdout()
      .command(['mr close', `${mockMergeRequest.iid}`])
      .exit(0)
      .it('mr was locked', (ctx) => {
        expect(ctx.stdout).to.contain(
          `Merge request !${mockMergeRequest.iid} (${mockMergeRequest.titleRaw}) can't be closed because it was locked`,
        );
      });

    // 通过 源分支名 关闭 mr
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
        // 模拟获取项目信息，命令中仅使用到了 project.id
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        api
          .get(`/api/web/v1/projects/1000/merge_requests?perPage=1&sourceBranch=${branch}&sort=created_desc`)
          .reply(200, [{ mergeRequest: mockMergeRequest }]);
        api.get(`/api/web/v1/projects/1000/merge_requests/${mockMergeRequest.iid}`).reply(200, {
          mergeRequest: mockMergeRequest,
          review: mockReview,
        });
        api.patch(`/api/web/v1/projects/1000/reviews/${mockReview.iid}/summary`).reply(500);
        api.put(`/api/web/v1/projects/1000/merge_requests/${mockMergeRequest.iid}/closed`).reply(200);
      })
      .stdout()
      .command(['mr close', branch, '-c "close with comment"'])
      .it('mr closed with comment', (ctx) => {
        expect(ctx.stdout).to.contain('Failed to add a comment');
        expect(ctx.stdout).to.contain(`Closed merge request !${mockMergeRequest.iid} (${mockMergeRequest.titleRaw})`);
      });

    // 关闭 mr 失败
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
        // 模拟获取项目信息，命令中仅使用到了 project.id
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        api.get(`/api/web/v1/projects/1000/merge_requests/${mockMergeRequest.iid}`).reply(200, {
          mergeRequest: mockMergeRequest,
          review: mockReview,
        });
        api.put(`/api/web/v1/projects/1000/merge_requests/${mockMergeRequest.iid}/closed`).reply(500);
      })
      .stdout()
      .command(['mr close', `${mockMergeRequest.iid}`])
      .it('fail to close', (ctx) => {
        expect(ctx.stdout).to.contain(
          `Failed to close merge request !${mockMergeRequest.iid} (${mockMergeRequest.titleRaw})`,
        );
      });
  });
});
