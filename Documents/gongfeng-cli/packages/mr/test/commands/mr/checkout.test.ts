import { expect, test } from '@oclif/test';
import * as base from '@tencent/gongfeng-cli-base';
import { setupEmptyDirectory, setupFixtureRepository } from '../../helpers/repositories';

const { file, git } = base;

describe('mr checkout', () => {
  describe('check login', () => {
    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return false;
        };
      })
      .stdout()
      .command(['mr checkout', '1'])
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
      .command(['mr checkout', '1'])
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
      .command(['mr checkout', '1'])
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
      .command(['mr checkout', '1'])
      .exit(0)
      .it('exit when project not found', (ctx) => {
        expect(ctx.stdout).to.contain('Project not found on GongFeng');
      });
  });

  // describe('with one remote found', () => {
  //   let repoPath: string;
  //   beforeEach(async () => {
  //     repoPath = 'xxxxx';
  //     // await git.addRemote(repoPath, 'origin', 'https://git.woa.com/code/cli');
  //   });
  //
  //   test
  //     .stub(base, 'checkAuth', () => {
  //       return () => {
  //         return true;
  //       };
  //     })
  //     .stub(file, 'readJsonSync', () => {
  //       return {};
  //     })
  //     .stub(base.vars, 'host', () => {
  //       return 'dev.git.woa.com';
  //     })
  //     .stub(process, 'cwd', () => {
  //       return repoPath;
  //     })
  //     // .nock('https://git.woa.com', (api) => {
  //     //   api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000, fullPath: 'code/cli' });
  //     //   api.get('/api/web/v1/projects/1000/merge_requests/1').reply(200, {
  //     //     mergeRequest: {
  //     //       sourceBranch: 'dev',
  //     //       sourceProjectId: 1000,
  //     //       targetProjectId: 1000,
  //     //     },
  //     //   });
  //     // })
  //     .stdout()
  //     .command(['mr checkout', '211'])
  //     .it('checkout source Branch diff from local branch when remote found ', async (ctx) => {
  //       const currentBranch = await git.getSymbolicRef(repoPath, 'HEAD');
  //       expect(currentBranch).to.equal('refs/heads/dev');
  //     });
  // });

  //
  // test
  //   .stub(base, 'checkAuth', () => {
  //     return () => {
  //       return true;
  //     };
  //   })
  //   .stub(file, 'readJsonSync', () => {
  //     return {};
  //   })
  //   .stub(base.vars, 'host', () => {
  //     return 'git.woa.com';
  //   })
  //   .stub(base.Git.prototype, 'remotes', () => {
  //     return [
  //       {
  //         name: 'origin',
  //         resolved: 'target',
  //         fetchUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //         pushUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //       },
  //     ];
  //   })
  //   .stub(base.Git.prototype, 'showRefs', () => {
  //     return 'fliel10338222';
  //   })
  //   .stub(base.Git.prototype, 'exec', () => {
  //     return '';
  //   })
  //   .nock('https://git.woa.com', (api) => {
  //     api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
  //     api.get('/api/web/v1/projects/1000/merge_requests/1').reply(200, {
  //       mergeRequest: {
  //         sourceBranch: 'dev',
  //         sourceProjectId: 1000,
  //         targetProjectId: 1000,
  //       },
  //     });
  //   })
  //   .stdout()
  //   .command(['mr checkout', '1'])
  //   .it('check out current project with mr branch exist', (ctx) => {
  //     expect(ctx.stdout).to.equal('');
  //   });
  //
  // test
  //   .stub(base, 'checkAuth', () => {
  //     return () => {
  //       return true;
  //     };
  //   })
  //   .stub(file, 'readJsonSync', () => {
  //     return {};
  //   })
  //   .stub(base.vars, 'host', () => {
  //     return 'git.woa.com';
  //   })
  //   .stub(base.Git.prototype, 'remotes', () => {
  //     return [
  //       {
  //         name: 'origin',
  //         resolved: 'target',
  //         fetchUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //         pushUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //       },
  //     ];
  //   })
  //   .stub(base.Git.prototype, 'showRefs', () => {
  //     return 'fliel10338222';
  //   })
  //   .stub(base.Git.prototype, 'exec', () => {
  //     return '';
  //   })
  //   .nock('https://git.woa.com', (api) => {
  //     api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
  //   })
  //   .stdout()
  //   .command(['mr checkout', 'dev'])
  //   .it('check out current project with branch exist', (ctx) => {
  //     expect(ctx.stdout).to.equal('');
  //   });
  //
  // test
  //   .stub(base, 'checkAuth', () => {
  //     return () => {
  //       return true;
  //     };
  //   })
  //   .stub(file, 'readJsonSync', () => {
  //     return {};
  //   })
  //   .stub(base.vars, 'host', () => {
  //     return 'git.woa.com';
  //   })
  //   .stub(base.Git.prototype, 'remotes', () => {
  //     return [
  //       {
  //         name: 'origin',
  //         resolved: 'target',
  //         fetchUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //         pushUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //       },
  //     ];
  //   })
  //   .stub(base.Git.prototype, 'showRefs', () => {
  //     return '';
  //   })
  //   .stub(base.Git.prototype, 'exec', () => {
  //     return '';
  //   })
  //   .nock('https://git.woa.com', (api) => {
  //     api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
  //   })
  //   .stdout()
  //   .command(['mr checkout', 'dev'])
  //   .it('check out current project with branch not exist', (ctx) => {
  //     expect(ctx.stdout).to.equal('');
  //   });
  //
  // test
  //   .stub(base, 'checkAuth', () => {
  //     return () => {
  //       return true;
  //     };
  //   })
  //   .stub(file, 'readJsonSync', () => {
  //     return {};
  //   })
  //   .stub(base.vars, 'host', () => {
  //     return 'git.woa.com';
  //   })
  //   .stub(base.Git.prototype, 'remotes', () => {
  //     return [
  //       {
  //         name: 'origin',
  //         fetchUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //         pushUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //       },
  //       {
  //         name: 'upstream',
  //         resolved: 'target',
  //         fetchUrl: {
  //           owner: 'code-fork',
  //           name: 'cli',
  //         },
  //         pushUrl: {
  //           owner: 'code-fork',
  //           name: 'cli',
  //         },
  //       },
  //     ];
  //   })
  //   .stub(base.Git.prototype, 'showRefs', () => {
  //     return '';
  //   })
  //   .stub(base.Git.prototype, 'exec', () => {
  //     return '';
  //   })
  //   .nock('https://git.woa.com', (api) => {
  //     api.get('/api/web/v1/projects/code-fork%2Fcli').reply(200, { id: 2000 });
  //     api.get('/api/web/v1/projects/2000/merge_requests/2').reply(200, {
  //       mergeRequest: {
  //         sourceBranch: 'test',
  //         sourceProjectId: 1000,
  //         targetProjectId: 2000,
  //       },
  //       sourceProject: {
  //         fullPath: 'code-fork/cli',
  //       },
  //     });
  //   })
  //   .stdout()
  //   .command(['mr checkout', '2'])
  //   .it('check out fork project mr with remote exist', (ctx) => {
  //     expect(ctx.stdout).to.equal('');
  //   });
  //
  // test
  //   .stub(base, 'checkAuth', () => {
  //     return () => {
  //       return true;
  //     };
  //   })
  //   .stub(file, 'readJsonSync', () => {
  //     return {};
  //   })
  //   .stub(base.vars, 'host', () => {
  //     return 'git.woa.com';
  //   })
  //   .stub(base.Git.prototype, 'remotes', () => {
  //     return [
  //       {
  //         name: 'origin',
  //         resolved: 'target',
  //         fetchUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //         pushUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //       },
  //     ];
  //   })
  //   .stub(base.Git.prototype, 'showRefs', () => {
  //     return '';
  //   })
  //   .stub(base.Git.prototype, 'exec', () => {
  //     return '';
  //   })
  //   .stub(base.Git.prototype, 'currentBranch', () => {
  //     return 'dev';
  //   })
  //   .nock('https://git.woa.com', (api) => {
  //     api.get('/api/web/v1/projects/code-fork%2Fcli').reply(200, { id: 2000 });
  //     api.get('/api/web/v1/projects/2000/merge_requests/2').reply(200, {
  //       mergeRequest: {
  //         sourceBranch: 'test',
  //         sourceProjectId: 1000,
  //         targetProjectId: 2000,
  //       },
  //       sourceProject: {
  //         fullPath: 'code-fork/cli',
  //       },
  //     });
  //   })
  //   .stdout()
  //   .command(['mr checkout', '2', '-R code-fork/cli'])
  //   .it('check out fork project mr with remote not exist', (ctx) => {
  //     expect(ctx.stdout).to.equal('');
  //   });
  //
  // test
  //   .stub(base, 'checkAuth', () => {
  //     return () => {
  //       return true;
  //     };
  //   })
  //   .stub(file, 'readJsonSync', () => {
  //     return {};
  //   })
  //   .stub(base.vars, 'host', () => {
  //     return 'git.woa.com';
  //   })
  //   .stub(base.Git.prototype, 'remotes', () => {
  //     return [
  //       {
  //         name: 'origin',
  //         resolved: 'target',
  //         fetchUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //         pushUrl: {
  //           owner: 'code',
  //           name: 'cli',
  //         },
  //       },
  //     ];
  //   })
  //   .stub(base.Git.prototype, 'showRefs', () => {
  //     return '';
  //   })
  //   .stub(base.Git.prototype, 'exec', () => {
  //     return '';
  //   })
  //   .stub(base.Git.prototype, 'currentBranch', () => {
  //     return 'dev';
  //   })
  //   .nock('https://git.woa.com', (api) => {
  //     api.get('/api/web/v1/projects/code-fork%2Fcli').reply(200, { id: 2000 });
  //   })
  //   .stdout()
  //   .command(['mr checkout', 'staging', '-R code-fork/cli'])
  //   .it('check out fork project branch with remote not exist', (ctx) => {
  //     expect(ctx.stdout).to.equal('');
  //   });
});
