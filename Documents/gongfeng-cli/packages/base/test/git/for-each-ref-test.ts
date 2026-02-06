import { setupEmptyDirectory, setupEmptyRepository, setupFixtureRepository } from '../helpers/repositories';
import { getBranches, getBranchesDifferingFromUpstream } from '../../src/git/for-each-ref';
import { BranchType } from '../../src/models/branch';
import { expect } from 'chai';

describe('git/for-each-ref', () => {
  let repoPath: string;

  describe('getBranches', () => {
    beforeEach(async () => {
      repoPath = await setupFixtureRepository('repo-with-many-refs');
    });

    it('fetches branches using for-each-ref', async () => {
      const branches = (await getBranches(repoPath)).filter((b) => b.type === BranchType.Local);

      expect(branches).to.have.lengthOf(3);

      const commitWithBody = branches[0];
      expect(commitWithBody.name).to.equal('commit-with-long-description');
      expect(commitWithBody.upstream).to.equal(null);
      expect(commitWithBody.tip.sha).to.equal('dfa96676b65e1c0ed43ca25492252a5e384c8efd');
      expect(commitWithBody.tip.author.name).to.equal('Brendan Forster');

      const commitNoBody = branches[1];
      expect(commitNoBody.name).to.equal('commit-with-no-body');
      expect(commitNoBody.upstream).to.equal(null);
      expect(commitNoBody.tip.sha).to.equal('49ec1e05f39eef8d1ab6200331a028fb3dd96828');
      expect(commitNoBody.tip.author.name).to.equal('Brendan Forster');
    });

    it('should return empty list for empty repo', async () => {
      const repo = await setupEmptyRepository();
      const branches = await getBranches(repo);
      expect(branches).to.have.lengthOf(0);
    });

    it('should return empty list for directory without a .git directory', async () => {
      const repo = setupEmptyDirectory();
      const branches = await getBranches(repo);
      expect(branches).to.have.lengthOf(0);
    });
  });

  describe('getBranchesDifferingFromUpstream', () => {
    beforeEach(async () => {
      repoPath = await setupFixtureRepository('repo-with-non-updated-branches');
    });

    it('filters branches differing from upstream using for-each-ref', async () => {
      const branches = await getBranchesDifferingFromUpstream(repoPath);
      const branchRefs = branches.map((branch) => branch.ref);
      expect(branchRefs).to.have.lengthOf(3);
      // All branches that are behind and/or ahead must be included
      expect(branchRefs).to.include('refs/heads/branch-behind');
      expect(branchRefs).to.include('refs/heads/branch-ahead');
      expect(branchRefs).to.include('refs/heads/branch-ahead-and-behind');

      expect(branchRefs).to.not.include('refs/heads/main');

      // Branches that are up to date shouldn't be included
      expect(branchRefs).to.not.include('refs/heads/branch-up-to-date');
    });
  });
});
