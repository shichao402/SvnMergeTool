import { setupEmptyRepository, setupFixtureRepository } from '../helpers/repositories';
import { expect } from 'chai';
import { determineTrackingBranch } from '../../src/git';

describe('branch tracking', () => {
  it('returns null where no merge ref found', async () => {
    const repoPath = await setupEmptyRepository();
    expect(await determineTrackingBranch(repoPath, 'master')).to.equal(null);
  });

  it('return the correct merge remote', async () => {
    const repoPath = await setupFixtureRepository('repo-with-multiple-remotes');
    expect(await determineTrackingBranch(repoPath, 'master')).to.deep.equal({
      remoteName: 'bassoon',
      branchName: 'master',
    });
  });
});
