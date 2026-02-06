import { setupEmptyRepository, setupFixtureRepository } from '../helpers/repositories';
import { Branch, BranchType } from '../../dist/models';
import { checkoutBranch, getSymbolicRef } from '../../src/git';
import { expect } from 'chai';
import { getBranches } from '../../dist/git/for-each-ref';
import { GitProcess } from '@tencent/code-dugite';
import { getStatusOrThrow } from '../helpers/status';

describe('git/checkout', () => {
  it('throws whern invalid characters are used for branch name', async () => {
    const repo = await setupEmptyRepository();
    const branch: Branch = {
      name: '..',
      nameWithoutRemote: '..',
      upstream: null,
      upstreamWithoutRemote: null,
      type: BranchType.Local,
      tip: {
        sha: '',
        author: {
          name: '',
          email: '',
          date: new Date(),
          tzOffset: 0,
        },
      },
      remoteName: null,
      upstreamRemoteName: null,
      ref: '',
    };

    let errorRaised = false;
    try {
      await checkoutBranch(repo, branch, false);
    } catch (error: any) {
      errorRaised = true;
      expect(error.message).to.equal('fatal: invalid reference: ..\n');
    }
    expect(errorRaised).to.equal(true);
  });

  it('can checkout a valid branch name in an existing repository', async () => {
    const path = await setupFixtureRepository('repo-with-many-refs');
    const branches = await getBranches(path, 'refs/heads/commit-with-long-description');
    if (branches.length === 0) {
      throw new Error('Could not find branch: commit-with-long-description');
    }
    const result = await checkoutBranch(path, branches[0], true);
    expect(result).to.equal(true);
  });

  it('can checkout a branch when it exist on multiple remotes', async () => {
    const path = await setupFixtureRepository('checkout-test-cases');
    const expectedBranch = 'first';
    const firstRemote = 'first-remote';
    const secondRemote = 'second-remote';
    const branches = await getBranches(path);
    const firstBranch = `${firstRemote}/${expectedBranch}`;
    const firstRemoteBranch = branches.find((b) => b.name === firstBranch);
    if (firstRemoteBranch === null) {
      throw new Error(`Could not find branch: '${firstBranch}'`);
    }

    const secondBranch = `${secondRemote}/${expectedBranch}`;
    const secondRemoteBranch = branches.find((b) => b.name === secondBranch);
    if (secondRemoteBranch === null) {
      throw new Error(`Could not find branch: '${secondBranch}'`);
    }

    await checkoutBranch(path, firstRemoteBranch!, true);
    const ref = await getSymbolicRef(path, 'HEAD');
    expect(`refs/heads/${expectedBranch}`).to.equal(ref);
  });

  describe('with submodules', () => {
    it('cleans up an submodule that no longer exists', async () => {
      const path = await setupFixtureRepository('test-submodule-checkouts');

      // put the repository into a known good state
      await GitProcess.exec(['checkout', 'add-private-repo', '-f', '--recurse-submodules'], path);

      const branches = await getBranches(path);
      const masterBranch = branches.find((b) => b.name === 'master');

      if (masterBranch === null) {
        throw new Error('Could not find branch: master');
      }

      await checkoutBranch(path, masterBranch!, true);

      const status = await getStatusOrThrow(path);

      expect(status.workingDirectory.files).to.have.length(0);
    });

    it('updates a changed submodule reference', async () => {
      const path = await setupFixtureRepository('test-submodule-checkouts');
      // put the repository into a known good state
      await GitProcess.exec(['checkout', 'master', '-f', '--recurse-submodules'], path);

      const branches = await getBranches(path);
      const devBranch = branches.find((b) => b.name === 'dev');

      if (devBranch === null) {
        throw new Error('Could not find branch: dev');
      }

      await checkoutBranch(path, devBranch!, true);

      const status = await getStatusOrThrow(path);
      expect(status.workingDirectory.files).to.have.lengthOf(0);
    });
  });
});
