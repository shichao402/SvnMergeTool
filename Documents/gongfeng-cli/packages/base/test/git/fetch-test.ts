import { Branch } from '../../src/models/branch';
import { setupFixtureRepository } from '../helpers/repositories';
import { getBranches, getBranchesDifferingFromUpstream } from '../../src/git/for-each-ref';
import { fastForwardBranches } from '../../src/git/fetch';
import { expect } from 'chai';
import * as Path from 'path';
import * as FSE from 'fs-extra';

function branchWithName(branches: ReadonlyArray<Branch>, name: string) {
  return branches.filter((branch) => branch.name === name)[0];
}

describe('git/fetch', () => {
  let repoPath: string;

  describe('fastForwardBranches', () => {
    beforeEach(async () => {
      repoPath = await setupFixtureRepository('repo-with-non-updated-branches');
    });

    it('fast-forwards branches using fetch', async () => {
      const eligibleBranches = await getBranchesDifferingFromUpstream(repoPath);
      await fastForwardBranches(repoPath, eligibleBranches);
      const resultBranches = await getBranches(repoPath);

      // Only the branch behind was updated to match its upstream
      const branchBehind = branchWithName(resultBranches, 'branch-behind');
      const branchBehindUpstream = branchWithName(resultBranches, branchBehind.upstream!);
      expect(branchBehindUpstream.tip.sha).to.equal(branchBehind.tip.sha);

      // The branch ahead is still ahead
      const branchAhead = branchWithName(resultBranches, 'branch-ahead');
      const branchAheadUpstream = branchWithName(resultBranches, branchAhead.upstream!);
      expect(branchAheadUpstream.tip.sha).to.not.equal(branchAhead.tip.sha);

      // The branch ahead and behind is still ahead and behind
      const branchAheadAndBehind = branchWithName(resultBranches, 'branch-ahead-and-behind');
      const branchAheadAndBehindUpstream = branchWithName(resultBranches, branchAheadAndBehind.upstream!);
      expect(branchAheadAndBehindUpstream.tip.sha).to.not.equal(branchAheadAndBehind.tip.sha);

      // The main branch hasn't been updated, since it's the current branch
      const mainBranch = branchWithName(resultBranches, 'main');
      const mainUpstream = branchWithName(resultBranches, mainBranch.upstream!);
      expect(mainUpstream.tip.sha).not.to.equal(mainBranch.tip.sha);

      // The up-to-date branch is still matching its upstream
      const upToDateBranch = branchWithName(resultBranches, 'branch-up-to-date');
      const upToDateBranchUpstream = branchWithName(resultBranches, upToDateBranch.upstream!);
      expect(upToDateBranchUpstream.tip.sha).to.equal(upToDateBranch.tip.sha);
    });

    // We want to avoid messing with the FETCH_HEAD file. Normally, it shouldn't
    // be something users would rely on, but we want to be good gitizens
    // (:badpundog:) when possible.
    it('does not change FETCH_HEAD after fast-forwarding branches with fetch', async () => {
      const eligibleBranches = await getBranchesDifferingFromUpstream(repoPath);

      const fetchHeadPath = Path.join(repoPath, '.git', 'FETCH_HEAD');
      const previousFetchHead = await FSE.readFile(fetchHeadPath, 'utf-8');

      await fastForwardBranches(repoPath, eligibleBranches);

      const currentFetchHead = await FSE.readFile(fetchHeadPath, 'utf-8');

      expect(currentFetchHead).to.equal(previousFetchHead);
    });
  });
});
