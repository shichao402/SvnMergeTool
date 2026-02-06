import { setupEmptyDirectory, setupEmptyRepository, setupFixtureRepository } from '../helpers/repositories';
import {
  addRemote,
  findDefaultRemote,
  getRemotes,
  getResolvedRemotes,
  removeRemote,
  setRemoteURL,
} from '../../src/git/remote';
import { expect } from 'chai';
import { setConfigValue } from '../../src/git/config';

describe('git/remote', () => {
  describe('gitRemotes', () => {
    it('should return both remotes', async () => {
      const repoPath = await setupFixtureRepository('repo-with-multiple-remotes');
      const result = await getRemotes(repoPath);
      expect(result[0].name).to.equal('bassoon');
      expect(result[0].fetchUrl!.href).to.equal('https://github.com/shiftkey/friendly-bassoon.git');
      expect(result[1].name).to.equal('origin');
      expect(result[1].fetchUrl!.href).to.equal('https://github.com/shiftkey/friendly-bassoon.git');
    });

    it('returns empty array for directory without a .git directory', async () => {
      const repoPath = setupEmptyDirectory();
      const remotes = await getRemotes(repoPath);
      expect(remotes).to.have.lengthOf(0);
    });
  });

  describe('getResolvedRemote', () => {
    it('should return the resolved remote', async () => {
      const repoPath = await setupFixtureRepository('repo-with-multiple-remotes');
      await setConfigValue(repoPath, 'remote.bassoon.gf-resolved', 'target');
      const result = await getResolvedRemotes(repoPath);
      expect(result[0].name).to.equal('bassoon');
      expect(result[0].resolved).to.equal('target');
      expect(result[0].fetchUrl!.href).to.equal('https://github.com/shiftkey/friendly-bassoon.git');
      expect(result[1].name).to.equal('origin');
      expect(result[1].fetchUrl!.href).to.equal('https://github.com/shiftkey/friendly-bassoon.git');
    });
  });

  describe('findDefaultRemote', () => {
    it('returns null for empty array', async () => {
      const result = await findDefaultRemote([]);
      expect(result).to.equal(null);
    });

    it('return origin when multiple remotes found', async () => {
      const repoPath = await setupFixtureRepository('repo-with-multiple-remotes');
      const remotes = await getRemotes(repoPath);
      const result = await findDefaultRemote(remotes);
      expect(result!.name).to.equal('origin');
    });

    it('returns something when origin removed', async () => {
      const repoPath = await setupFixtureRepository('repo-with-multiple-remotes');
      await removeRemote(repoPath, 'origin');
      const remotes = await getRemotes(repoPath);
      const result = await findDefaultRemote(remotes);
      expect(result!.name).to.equal('bassoon');
    });

    it('returns null for new repository', async () => {
      const repoPath = await setupEmptyRepository();
      const remotes = await getRemotes(repoPath);
      const result = await findDefaultRemote(remotes);
      expect(result).to.equal(null);
    });
  });

  describe('addRemote', () => {
    it('can set origin and return it as default', async () => {
      const repoPath = await setupEmptyRepository();
      await addRemote(repoPath, 'origin', 'https://git.woa.com/code/cli');
      const remotes = await getRemotes(repoPath);
      const result = await findDefaultRemote(remotes);
      expect(result!.name).to.equal('origin');
    });
  });

  describe('removeRemote', () => {
    it('silently fails where remote not defined', async () => {
      const repoPath = await setupEmptyRepository();
      expect(function () {
        return removeRemote(repoPath, 'origin');
      }).to.not.throw();
    });
  });

  describe('setRemoteURL', () => {
    let repoPath: string;
    const remoteName = 'origin';
    const remoteUrl = 'https://fakeweb.com/owner/name';
    const newUrl = 'https://git.woa.com/code/cli';

    beforeEach(async () => {
      repoPath = await setupEmptyRepository();
      await addRemote(repoPath, remoteName, remoteUrl);
    });

    it('can set the url for an existing remote', async () => {
      expect(await setRemoteURL(repoPath, remoteName, newUrl)).to.equal(true);

      const remotes = await getRemotes(repoPath);
      expect(remotes).to.have.lengthOf(1);
      expect(remotes[0].fetchUrl!.href).to.equal(newUrl);
    });
  });
});
