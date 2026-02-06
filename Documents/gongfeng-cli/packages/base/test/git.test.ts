import * as childProcess from 'child_process';
import { expect, fancy } from 'fancy-test';
import { GitShell, Remote } from '../src';
import * as gitUrlParse from 'git-url-parse';

const git = new GitShell();

describe('git', () => {
  it('parse remotes', () => {
    const list = [
      'origin\thttps://github.com/foo/bar  (fetch)',
      'origin\thttps://github.com/foo/bar  (push)',
      'gongfeng\thttps://git.woa.com/myapp.git  (fetch)',
      'gongfeng\thttps://git.woa.com/myapp.git  (push)',
      'dev  https://git.woa.com/code/cli/aaa/web.git (fetch)',
      'dev  https://git.woa.com/code/cli/aaa/web.git (push)',
    ];
    const remotes = git.parseRemotes(list);
    expect(remotes[0].name).to.equal('origin');
    expect(remotes[0].fetchUrl?.href).to.equal('https://github.com/foo/bar');
    expect(remotes[0].pushUrl?.href).to.equal('https://github.com/foo/bar');
    expect(remotes[1].name).to.equal('gongfeng');
    expect(remotes[1].fetchUrl?.href).to.equal('https://git.woa.com/myapp.git');
    expect(remotes[1].pushUrl?.href).to.equal('https://git.woa.com/myapp.git');
    expect(remotes[2].pushUrl?.owner).to.equal('code/cli/aaa');
    expect(remotes[2].pushUrl?.name).to.equal('web');
  });

  fancy
    .stub(git, 'listRemotes', () => {
      return [
        'origin\thttps://github.com/foo/bar  (fetch)',
        'origin\thttps://github.com/foo/bar  (push)',
        'gongfeng\thttps://git.woa.com/myapp.git  (fetch)',
        'gongfeng\thttps://git.woa.com/myapp.git  (push)',
        'dev  https://git.woa.com/code/cli/aaa/web.git (fetch)',
        'dev  https://git.woa.com/code/cli/aaa/web.git (push)',
      ];
    })
    .stub(git, 'exec', () => {
      return `remote.origin.gf-resolved base
remote.origin.gf-resolved base
remote.gongfeng.gf-resolved target
`;
    })
    .it('gets the remotes', () => {
      const remotes = git.remotes();
      expect(remotes[0].name).to.equal('origin');
      expect(remotes[0].fetchUrl?.href).to.equal('https://github.com/foo/bar');
      expect(remotes[0].pushUrl?.href).to.equal('https://github.com/foo/bar');
      expect(remotes[0].resolved).to.equal('base');
      expect(remotes[1].name).to.equal('gongfeng');
      expect(remotes[1].fetchUrl?.href).to.equal('https://git.woa.com/myapp.git');
      expect(remotes[1].pushUrl?.href).to.equal('https://git.woa.com/myapp.git');
      expect(remotes[1].resolved).to.equal('target');
      expect(remotes[2].pushUrl?.owner).to.equal('code/cli/aaa');
      expect(remotes[2].pushUrl?.name).to.equal('web');
      expect(remotes[2].resolved).to.equal(undefined);
    });

  fancy
    .stub(git, 'listRemotes', () => {
      return [
        'origin\thttps://github.com/foo/bar  (fetch)',
        'origin\thttps://github.com/foo/bar  (push)',
        'gongfeng\thttps://git.woa.com/myapp.git  (fetch)',
        'gongfeng\thttps://git.woa.com/myapp.git  (push)',
        'dev  https://git.woa.com/code/cli/aaa/web.git (fetch)',
        'dev  https://git.woa.com/code/cli/aaa/web.git (push)',
      ];
    })
    .stub(git, 'exec', () => {
      return `remote.origin.gf-resolved base
remote.origin.gf-resolved base
remote.gongfeng.gf-resolved target
`;
    })
    .it('remote url with target', () => {
      const remote = git.remoteUrl();
      expect(remote).to.equal('https://git.woa.com/myapp.git');
    });

  fancy
    .stub(git, 'listRemotes', () => {
      return [
        'origin\thttps://github.com/foo/bar  (fetch)',
        'origin\thttps://github.com/foo/bar  (push)',
        'gongfeng\thttps://git.woa.com/myapp.git  (fetch)',
        'gongfeng\thttps://git.woa.com/myapp.git  (push)',
        'dev  https://git.woa.com/code/cli/aaa/web.git (fetch)',
        'dev  https://git.woa.com/code/cli/aaa/web.git (push)',
      ];
    })
    .stub(git, 'exec', () => {
      return '';
    })
    .it('remote url with origin', () => {
      const remote = git.remoteUrl();
      expect(remote).to.equal('https://github.com/foo/bar');
    });

  fancy
    .stub(childProcess, 'execSync', () => {
      const err: any = new Error('some other message');
      err.code = 'ENOENT';
      throw err;
    })
    .it('rethrows other git error', () => {
      // const git = new Git();
      expect(() => {
        git.exec('version');
      }).to.throw('some other message');
    });

  fancy
    .stub(git, 'exec', () => {
      return 'branch-name\n';
    })
    .it('get current branch 1', () => {
      expect(git.currentBranch()).to.equal('branch-name');
    });

  fancy
    .stub(git, 'exec', () => {
      return 'refs/heads/branch-name\n';
    })
    .it('get current branch 2', () => {
      expect(git.currentBranch()).to.equal('branch-name');
    });

  fancy
    .stub(git, 'exec', () => {
      return 'refs/heads/branch\u00A0with\u00A0non\u00A0breaking\u00A0space\n';
    })
    .it('get current branch 3', () => {
      expect(git.currentBranch()).to.equal('branch\u00A0with\u00A0non\u00A0breaking\u00A0space');
    });

  fancy
    .stub(git, 'exec', () => {
      return 'packages/cli/\n';
    })
    .it('get path from repo root', () => {
      expect(git.pathFromRepoRoot()).to.equal('packages/cli/');
    });

  fancy
    .stub(git, 'exec', () => {
      return '/Users/xxxx/projects/cli\n';
    })
    .it('top level dir', () => {
      expect(git.pathFromRepoRoot()).to.equal('/Users/xxxx/projects/cli');
    });

  fancy
    .stub(git, 'exec', () => {
      return '\n\nd83d013fbdc68daeca5e4f33f2c10bad0afcb5b8,chore(base): 提供访问工蜂的api实例\n';
    })
    .it('get last commit', () => {
      const commit = git.lastCommit();
      expect(commit.sha).to.equal('\n\nd83d013fbdc68daeca5e4f33f2c10bad0afcb5b8');
      expect(commit.title).to.equal('chore(base): 提供访问工蜂的api实例\n');
    });

  fancy
    .stub(git, 'exec', () => {
      return '创建符合工蜂开发规范的子命令项目';
    })
    .it('get commit body', () => {
      const body = git.commitBody('d35c5dab');
      expect(body).to.equal('创建符合工蜂开发规范的子命令项目');
    });

  fancy
    .stub(git, 'exec', () => {
      return (
        ' M packages/auth/src/commands/auth/login.ts\n' +
        ' M packages/base/src/git.ts\n' +
        ' M packages/base/test/git.test.ts\n' +
        '?? packages/env/src/locales/\n'
      );
    })
    .it('get uncommitted count', () => {
      const count = git.unCommittedChangeCount();
      expect(count).to.equal(4);
    });

  it('output lines', () => {
    const lines = git.outputLines('\naaa\nwwwww\n');
    expect(lines.length).to.equal(3);
  });

  fancy
    .stub(git, 'exec', () => {
      return `489464b48be38e78acd96bb56311436ac3f7992c,chore(base): 补充测试
7ba8a005d8e84c6fcd25055651d87dae8c1013a8,feat(cli): cli命令默认需要先登录，允许通过skip参数跳过
4db57c51012cc5379c0bb0925aa5e225d7f301e7,fix(cli): 删除多余逗号
6f4927f983fef6ff98f9316a79ca19a1e9485728,fix(cli): 修改配置和各个环境的dsn
c3dc31d5e69e4b788c1f50d43726041d8143721c,feat(cli): 新增异常监控功能
3e16d665e2982f3d8e6382f74f54c749a13ce978,feat(cli): test 支持 i18n 初始化
55593ef5ab7bdac59dbc493bd710bbe854cc5382,feat(cli): cli color
8e06ad0fa9e9262937e4b7437dfa9d25b126deea,feat(cli): gf auth login & logout
9b60cf1e3353ed8af20b27a95028ac1e895c52d0,feat(cli): cli 子项目eslint 和 测试覆盖率配置
3f51f537ecd6f6409195fb80facbd53c68004eae,feat(cli): cli extension 子命令
d35c5dabeb96522eeb3e624d5257878f5889c094,feat(cli): cli extension 子命令
e301d10fa1ff7e2c66c234e7d5275cdac85bdb41,feat(cli): auth子命令对 base模块的依赖
021dfc47beaf3246b15a4009cfd01a62ffd54008,feat(cli): 补充测试用例
d3784bb3e9971edbe53073d7e079e1886a111383,feat(cli): 补充测试用例
e43f76cf998fb2820a4df8bb8feebaf2ae9abfd7,feat(cli): cli 支持国际化
0c0e7b9e117eedc9c940e6c2dedae174703a14e7,feat(cli): 判断灯塔key 是否存在
28068d5e63d3ff9bf1b8b9be81621fcebdf363fe,feat(cli): 优化多环境切换逻辑
0f5d0903b7386a070e0a76620899b1b40b71a6a4,feat(cli): 数据监控上报到灯塔
`;
    })
    .it('get commits', () => {
      const commits = git.commits('master', 'dev');
      expect(commits.length).to.equal(18);
      expect(commits[0].sha).to.equal('489464b48be38e78acd96bb56311436ac3f7992c');
    });

  fancy
    .stub(git, 'exec', () => {
      return `branch.master.remote origin
branch.master.merge refs/heads/master
`;
    })
    .it('read branch config', () => {
      const config = git.readBranchConfig('master');
      expect(config.remoteName).to.equal('origin');
      expect(config.mergeRef).to.equal('refs/heads/master');
    });

  fancy
    .stub(git, 'exec', () => {
      return `branch.master.remote https://git.woa.com/test.git
branch.master.merge refs/heads/master
`;
    })
    .it('read branch config2', () => {
      const config = git.readBranchConfig('master');
      expect(config.remoteUrl?.href).to.equal('https://git.woa.com/test.git');
      expect(config.mergeRef).to.equal('refs/heads/master');
    });

  fancy
    .stub(git, 'exec', () => {
      return '';
    })
    .it('read branch config3', () => {
      const config = git.readBranchConfig('master');
      expect(config.remoteUrl).to.equal(undefined);
      expect(config.mergeRef).to.equal(undefined);
    });

  fancy
    .stub(git, 'exec', () => {
      return `d83d013fbdc68daeca5e4f33f2c10bad0afcb5b8 HEAD
d83d013fbdc68daeca5e4f33f2c10bad0afcb5b8 refs/remotes/origin/master
744a9febdc48f76ab17bfae84a811ad371e9df8d refs/remotes/origin/dev
`;
    })
    .it('show refs', () => {
      const refs = git.showRefs('HEAD', 'refs/remotes/origin/master', 'refs/remotes/origin/dev');
      expect(refs.length).to.equal(3);
      expect(refs[0].name).to.equal('HEAD');
      expect(refs[0].hash).to.equal('d83d013fbdc68daeca5e4f33f2c10bad0afcb5b8');
    });

  fancy
    .stub(git, 'readBranchConfig', () => {
      return '';
    })
    .stub(git, 'showRefs', () => {
      return [
        {
          hash: 'abc',
          name: 'HEAD',
        },
      ];
    })
    .it('determine tracking branch empty', () => {
      const remotes: Remote[] = [
        {
          name: 'origin',
          fetchUrl: gitUrlParse('https://git.woa.com/hubot/Spoon-Knife'),
          pushUrl: gitUrlParse('https://git.woa.com/hubot/Spoon-Knife'),
        },
        {
          name: 'upstream',
          fetchUrl: gitUrlParse('https://git.woa.com/octocat/Spoon-Knife'),
          pushUrl: gitUrlParse('https://git.woa.com/octocat/Spoon-Knife'),
        },
      ];
      const ref = git.determineTrackingBranch(remotes, 'feature');
      expect(ref).to.equal(null);
    });

  fancy
    .stub(git, 'readBranchConfig', () => {
      return '';
    })
    .stub(git, 'showRefs', () => {
      // git show-ref --verify -- HEAD refs/remotes/origin/feature refs/remotes/upstream/feature
      return [
        {
          hash: 'abc',
          name: 'HEAD',
        },
        {
          hash: 'bca',
          name: 'refs/remotes/origin/feature',
        },
      ];
    })
    .it('determine tracking branch no match', () => {
      const remotes: Remote[] = [
        {
          name: 'origin',
          fetchUrl: gitUrlParse('https://git.woa.com/hubot/Spoon-Knife'),
          pushUrl: gitUrlParse('https://git.woa.com/hubot/Spoon-Knife'),
        },
        {
          name: 'upstream',
          fetchUrl: gitUrlParse('https://git.woa.com/octocat/Spoon-Knife'),
          pushUrl: gitUrlParse('https://git.woa.com/octocat/Spoon-Knife'),
        },
      ];
      const ref = git.determineTrackingBranch(remotes, 'feature');
      expect(ref).to.equal(null);
    });

  fancy
    .stub(git, 'readBranchConfig', () => {
      return '';
    })
    .stub(git, 'showRefs', () => {
      // git show-ref --verify -- HEAD refs/remotes/origin/feature refs/remotes/upstream/feature
      return [
        {
          hash: 'deadbeef',
          name: 'HEAD',
        },
        {
          hash: 'deadb00f',
          name: 'refs/remotes/origin/feature',
        },
        {
          hash: 'deadbeef',
          name: 'refs/remotes/upstream/feature',
        },
      ];
    })
    .it('determine tracking branch has match', () => {
      const remotes: Remote[] = [
        {
          name: 'origin',
          fetchUrl: gitUrlParse('https://git.woa.com/hubot/Spoon-Knife'),
          pushUrl: gitUrlParse('https://git.woa.com/hubot/Spoon-Knife'),
        },
        {
          name: 'upstream',
          fetchUrl: gitUrlParse('https://git.woa.com/octocat/Spoon-Knife'),
          pushUrl: gitUrlParse('https://git.woa.com/octocat/Spoon-Knife'),
        },
      ];
      const ref = git.determineTrackingBranch(remotes, 'feature');
      expect(ref?.remoteName).to.equal('upstream');
      expect(ref?.branchName).to.equal('feature');
    });

  fancy
    .stub(git, 'readBranchConfig', () => {
      return {
        remoteName: 'origin',
        mergeRef: 'refs/heads/great-feat',
      };
    })
    .stub(git, 'showRefs', () => {
      // git show-ref --verify -- HEAD refs/remotes/origin/feature refs/remotes/upstream/feature
      return [
        {
          hash: 'deadbeef',
          name: 'HEAD',
        },
        {
          hash: 'deadb00f',
          name: 'refs/remotes/origin/feature',
        },
      ];
    })
    .it('determine tracking branch tracking config', () => {
      const remotes: Remote[] = [
        {
          name: 'origin',
          fetchUrl: gitUrlParse('https://git.woa.com/hubot/Spoon-Knife'),
          pushUrl: gitUrlParse('https://git.woa.com/hubot/Spoon-Knife'),
        },
      ];
      const ref = git.determineTrackingBranch(remotes, 'feature');
      expect(ref).to.equal(null);
    });

  fancy
    .stub(git, 'exec', () => {
      return '';
    })
    .it('local branch not exists', () => {
      expect(git.isLocalBranchExists('test')).to.equal(false);
    });

  fancy
    .stub(git, 'exec', () => {
      return 'test';
    })
    .it('local branch exists', () => {
      expect(git.isLocalBranchExists('test')).to.equal(true);
    });

  fancy
    .stub(git, 'exec', () => {
      return '';
    })
    .it('remote branch not exists', () => {
      expect(git.isRemoteBranchExists('origin', 'test')).to.equal(false);
    });

  fancy
    .stub(git, 'exec', () => {
      return '2934447141d87e2d555062700b6ba0c46b1fc624\t refs/heads/test';
    })
    .it('remote branch exists', () => {
      expect(git.isRemoteBranchExists('origin', 'test')).to.equal(true);
    });
});
