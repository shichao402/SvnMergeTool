import { setupFixtureRepository } from '../helpers/repositories';
import { getChangedFiles, getCommits } from '../../src/git/log';
import { expect } from 'chai';
import { setupLocalConfig } from '../../src/utils/local-config';
import { AppFileStatusKind } from '../../src/models/status';

describe('git log', () => {
  let repoPath: string;
  beforeEach(async () => {
    repoPath = await setupFixtureRepository('test-repo-with-tags');
  });

  describe('getCommits', () => {
    it('loads history', async () => {
      const commits = await getCommits(repoPath, 'HEAD', 100);
      expect(commits).to.have.lengthOf(5);

      const firstCommit = commits[commits.length - 1];
      expect(firstCommit.summary).to.equal('first');
      expect(firstCommit.sha).to.equal('7cd6640e5b6ca8dbfd0b33d0281ebe702127079c');
      expect(firstCommit.shortSha).to.equal('7cd6640');
    });

    it('handles repository with HEAD file on disk', async () => {
      const path = await setupFixtureRepository('repository-with-HEAD-file');
      const commits = await getCommits(path, 'HEAD', 100);
      expect(commits).to.have.lengthOf(2);
    });

    it('handles repository with signed commit and log.showSignature set', async () => {
      const path = await setupFixtureRepository('just-doing-some-signing');
      // ensure the default config is to try and show signatures
      // this should be overriden by the `getCommits` function as it may not
      // have a valid GPG agent configured
      await setupLocalConfig(path, [['log.showSignature', 'true']]);

      const commits = await getCommits(path, 'HEAD', 100);
      expect(commits).to.have.lengthOf(1);
      expect(commits[0].sha).to.equal('415e4987158c49c383ce7114e0ef00ebf4b070c1');
      expect(commits[0].shortSha).to.equal('415e498');
    });

    it('parse tags', async () => {
      const commits = await getCommits(repoPath, 'HEAD', 100);
      expect(commits).to.have.lengthOf(5);
      expect(commits[0].tags).to.include('important');
      expect(commits[1].tags).to.include('tentative', 'less-important');
      expect(commits[2].tags).to.have.lengthOf(0);
    });
  });

  describe('getChangedFiles', () => {
    it('loads the files changed in the commit', async () => {
      const changedData = await getChangedFiles(repoPath, '7cd6640e5b6ca8dbfd0b33d0281ebe702127079c');

      expect(changedData.files).to.have.lengthOf(1);
      expect(changedData.files[0].path).to.equal('README.md');
      expect(changedData.files[0].status.kind).to.equal(AppFileStatusKind.New);
    });

    it('detects renames', async () => {
      const path = await setupFixtureRepository('rename-history-detection');

      const first = await getChangedFiles(path, '55bdecb');
      expect(first.files).to.have.lengthOf(1);
      expect(first.files[0].path).to.equal('NEWER.md');
      expect(first.files[0].status).to.include({
        kind: AppFileStatusKind.Renamed,
        oldPath: 'NEW.md',
      });

      const second = await getChangedFiles(path, 'c898ca8');
      expect(second.files).to.have.lengthOf(1);
      expect(second.files[0].path).to.equal('NEW.md');
      expect(second.files[0].status).to.include({
        kind: AppFileStatusKind.Renamed,
        oldPath: 'OLD.md',
      });
    });

    it('detects copies', async () => {
      const path = await setupFixtureRepository('copies-history-detection');
      // ensure the test repository is configured to detect copies
      await setupLocalConfig(path, [['diff.renames', 'copies']]);

      const changeData = await getChangedFiles(path, 'a500bf415');
      expect(changeData.files).to.have.lengthOf(2);

      expect(changeData.files[0].path).to.equal('duplicate-with-edits.md');
      expect(changeData.files[0].status).to.include({
        kind: AppFileStatusKind.Copied,
        oldPath: 'initial.md',
      });
      expect(changeData.files[1].path).to.equal('duplicate.md');
      expect(changeData.files[1].status).to.include({
        kind: AppFileStatusKind.Copied,
        oldPath: 'initial.md',
      });
    });

    it('handles commit when HEAD exist on disk', async () => {
      const changeData = await getChangedFiles(repoPath, 'HEAD');
      expect(changeData.files).to.have.lengthOf(1);
      expect(changeData.files[0].path).to.equal('README.md');
      expect(changeData.files[0].status.kind).to.equal(AppFileStatusKind.Modified);
    });

    it('detects submodule changes within commits', async () => {
      const path = await setupFixtureRepository('submodule-basic-setup');

      const changeData = await getChangedFiles(path, 'HEAD');
      expect(changeData.files).to.have.lengthOf(2);
      expect(changeData.files[1].path).to.equal('foo/submodule');
      expect(changeData.files[1].status.submoduleStatus).to.include({
        commitChanged: false,
        untrackedChanges: false,
        modifiedChanges: false,
      });
    });
  });
});
