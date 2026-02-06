import { expect, test } from '@oclif/test';
import * as base from '@tencent/gongfeng-cli-base';
import { setupEmptyDirectory, setupFixtureRepository } from '../../helpers/repositories';

const { file, git } = base;

describe('mr edit', () => {
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

  // describe('edit mr with flags', () => {
  //   let repoPath: string;
  //   beforeEach(async () => {
  //     repoPath = await setupFixtureRepository('test-repo');
  //   });
  //   test
  //     // .stub(base, 'checkAuth', () => {
  //     //   return () => {
  //     //     return true;
  //     //   };
  //     // })
  //     // .stub(file, 'readJsonSync', () => {
  //     //   return {};
  //     // })
  //     .stub(process, 'cwd', () => {
  //       return repoPath;
  //     })
  //     // .nock('https://git.woa.com', (api) => {
  //     //   api.get('/api/web/v1/projects/code%2Fcli').reply(200, undefined);
  //     // })
  //     .stdout()
  //     .command([
  //       'mr edit',
  //       '365',
  //       '-t 88888',
  //       '-d 333333',
  //     ])
  //     .exit(0)
  //     .it('exit when project not found', (ctx) => {
  //       expect(ctx.stdout).to.contain('Project not found on GongFeng');
  //     });
  // });
});
