import { formatAsLocalRef, getRefSha, getSymbolicRef } from '../../src/git/refs';
import { expect } from 'chai';
import { setupEmptyRepository, setupFixtureRepository } from '../helpers/repositories';

describe('git/refs', () => {
  describe('formatAsLocalRef', () => {
    it('formats the common branch syntax', () => {
      const result = formatAsLocalRef('master');
      expect(result).to.equal('refs/heads/master');
    });

    it('formats an explicit heads/ prefix', () => {
      const result = formatAsLocalRef('heads/something');
      expect(result).to.equal('refs/heads/something');
    });

    it('formats when a remote is included', () => {
      const result = formatAsLocalRef('heads/cli/master');
      expect(result).to.equal('refs/heads/cli/master');
    });
  });

  describe('getSymbolicRef', () => {
    it('resolves a valid symbolic ref', async () => {
      const repoPath = await setupEmptyRepository();
      const ref = await getSymbolicRef(repoPath, 'HEAD');
      expect(ref).to.equal('refs/heads/master');
    });

    it('does not resolve a missing ref', async () => {
      const repoPath = await setupEmptyRepository();
      const ref = await getSymbolicRef(repoPath, 'BAR');
      expect(ref).to.equal(null);
    });
  });

  describe('getRef', () => {
    let repoPath: string;
    beforeEach(async () => {
      repoPath = await setupFixtureRepository('test-repo');
    });

    it('returns null when ref not exist', async () => {
      expect(await getRefSha(repoPath, 'foo')).to.equal(null);
    });

    it('returns hash and name when ref exist', async () => {
      expect(await getRefSha(repoPath, 'HEAD')).to.equal('04c7629c588c74659f03dda5e5fb3dd8d6862dfa HEAD');
      expect(await getRefSha(repoPath, 'refs/heads/master')).to.equal(
        '04c7629c588c74659f03dda5e5fb3dd8d6862dfa refs/heads/master',
      );
    });
  });
});
