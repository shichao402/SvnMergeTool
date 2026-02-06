import * as path from 'path';
import * as FSE from 'fs-extra';
import { GitProcess } from '@tencent/code-dugite';
import { getStatusOrThrow } from '../helpers/status';
import {
  setupConflictedRepoWithMultipleFiles,
  setupEmptyDirectory,
  setupEmptyRepository,
  setupFixtureRepository,
} from '../helpers/repositories';
import { AppFileStatusKind, GitStatusEntry, isManualConflict, UnmergedEntrySummary } from '../../src/models/status';
import { getStatus, isConflictedFile } from '../../src/git/status';
import { expect } from 'chai';
import { generateString } from '../helpers/random-data';
import { setupLocalConfig } from '../../src/utils/local-config';

describe('git/status', () => {
  describe('getStatus', () => {
    let repoPath: string;

    describe('with conflicted repo', () => {
      let filePath: string;

      beforeEach(async () => {
        repoPath = await setupConflictedRepoWithMultipleFiles();
        filePath = path.join(repoPath, 'foo');
      });

      it('parses conflicted files with markers', async () => {
        const status = await getStatusOrThrow(repoPath);
        const files = status.workingDirectory.files;
        expect(files).to.have.lengthOf(5);

        const conflictedFiles = files.filter((f) => f.status.kind === AppFileStatusKind.Conflicted);
        expect(conflictedFiles).to.have.lengthOf(4);

        const fooFile = files.find((f) => f.path === 'foo')!;
        expect(fooFile.status).to.deep.equal({
          kind: AppFileStatusKind.Conflicted,
          entry: {
            kind: 'conflicted',
            action: UnmergedEntrySummary.BothModified,
            them: GitStatusEntry.UpdatedButUnmerged,
            us: GitStatusEntry.UpdatedButUnmerged,
            submoduleStatus: undefined,
          },
          conflictMarkerCount: 3,
        });

        const bazFile = files.find((f) => f.path === 'baz')!;
        expect(bazFile.status).to.deep.equal({
          kind: AppFileStatusKind.Conflicted,
          entry: {
            kind: 'conflicted',
            action: UnmergedEntrySummary.BothAdded,
            them: GitStatusEntry.Added,
            us: GitStatusEntry.Added,
            submoduleStatus: undefined,
          },
          conflictMarkerCount: 3,
        });

        const catFile = files.find((f) => f.path === 'cat')!;
        expect(catFile.status).to.deep.equal({
          kind: AppFileStatusKind.Conflicted,
          entry: {
            kind: 'conflicted',
            action: UnmergedEntrySummary.BothAdded,
            them: GitStatusEntry.Added,
            us: GitStatusEntry.Added,
            submoduleStatus: undefined,
          },
          conflictMarkerCount: 3,
        });
      });

      it('parses conflicted files without markers', async () => {
        const status = await getStatusOrThrow(repoPath);
        const files = status.workingDirectory.files;
        expect(files).to.have.lengthOf(5);
        expect(files.filter((f) => f.status.kind === AppFileStatusKind.Conflicted)).to.have.lengthOf(4);

        const barFile = files.find((f) => f.path === 'bar')!;
        expect(barFile.status).to.deep.equal({
          kind: AppFileStatusKind.Conflicted,
          entry: {
            kind: 'conflicted',
            action: UnmergedEntrySummary.DeletedByThem,
            us: GitStatusEntry.UpdatedButUnmerged,
            them: GitStatusEntry.Deleted,
            submoduleStatus: undefined,
          },
        });
      });

      it('parses conflicted files resulting from poping a stash', async () => {
        const repo = await setupEmptyRepository();
        const readme = path.join(repo, 'README.md');
        await FSE.writeFile(readme, '');
        await GitProcess.exec(['add', 'README.md'], repo);
        await GitProcess.exec(['commit', '-m', 'initial commit'], repo);

        // write a change to the readme into the stash
        await FSE.appendFile(readme, generateString());
        await GitProcess.exec(['stash'], repo);

        // write a different change to the README and commit it
        await FSE.appendFile(readme, generateString());
        await GitProcess.exec(['commit', '-am', 'later commit'], repo);

        // pop the stash to introduce a conflict into the index
        await GitProcess.exec(['stash', 'pop'], repo);

        const status = await getStatusOrThrow(repo);
        const files = status.workingDirectory.files;
        expect(files).to.have.lengthOf(1);

        const conflictedFiles = files.filter((f) => f.status.kind === AppFileStatusKind.Conflicted);
        expect(conflictedFiles).to.have.lengthOf(1);
      });

      it('parses resolved files', async () => {
        await FSE.writeFile(filePath, 'b1b2');
        const status = await getStatusOrThrow(repoPath);
        const files = status.workingDirectory.files;
        expect(files).to.have.lengthOf(5);

        // all files are now considered conflicted
        expect(files.filter((f) => f.status.kind === AppFileStatusKind.Conflicted)).to.have.lengthOf(4);

        const file = files.find((f) => f.path === 'foo');
        expect(file!.status).to.deep.equal({
          kind: AppFileStatusKind.Conflicted,
          entry: {
            kind: 'conflicted',
            action: UnmergedEntrySummary.BothModified,
            them: GitStatusEntry.UpdatedButUnmerged,
            us: GitStatusEntry.UpdatedButUnmerged,
            submoduleStatus: undefined,
          },
          conflictMarkerCount: 0,
        });
      });
    });

    describe('with conflicted images repo', () => {
      beforeEach(async () => {
        repoPath = await setupFixtureRepository('detect-conflict-in-binary-file');
        await GitProcess.exec(['checkout', 'make-a-change'], repoPath);
      });

      it('parses conflicted image file on merge', async () => {
        await GitProcess.exec(['merge', 'master'], repoPath);

        const status = await getStatusOrThrow(repoPath);
        const files = status.workingDirectory.files;
        expect(files).to.have.lengthOf(1);

        const file = files[0];
        expect(file.status.kind).to.equal(AppFileStatusKind.Conflicted);
        expect(isConflictedFile(file.status) && isManualConflict(file.status)).to.equal(true);
      });

      it('parses conflicted image file on merge after removing', async () => {
        await GitProcess.exec(['rm', 'my-cool-image.png'], repoPath);
        await GitProcess.exec(['commit', '-am', 'removed the image'], repoPath);
        await GitProcess.exec(['merge', 'master'], repoPath);

        const status = await getStatusOrThrow(repoPath);
        const files = status.workingDirectory.files;
        expect(files).to.have.lengthOf(1);

        const file = files[0];
        expect(file.status.kind).to.equal(AppFileStatusKind.Conflicted);
        expect(isConflictedFile(file.status) && isManualConflict(file.status)).to.equal(true);
      });
    });

    describe('with unconflicted repo', () => {
      beforeEach(async () => {
        repoPath = await setupFixtureRepository('test-repo');
      });

      it('parses changed files', async () => {
        await FSE.writeFile(path.join(repoPath, 'README.md'), 'Hello world\n');

        const status = await getStatusOrThrow(repoPath);
        const files = status.workingDirectory.files;
        expect(files).to.have.lengthOf(1);

        const file = files[0];
        expect(file.path).to.equal('README.md');
        expect(file.status.kind).to.equal(AppFileStatusKind.Modified);
      });

      it('returns an empty array when there are no changes', async () => {
        const status = await getStatusOrThrow(repoPath);
        const files = status.workingDirectory.files;
        expect(files).to.have.lengthOf(0);
      });

      it('reflects renames', async () => {
        const repo = await setupEmptyRepository();
        await FSE.writeFile(path.join(repo, 'foo'), 'foo\n');

        await GitProcess.exec(['add', 'foo'], repo);
        await GitProcess.exec(['commit', '-m', 'Initial commit'], repo);
        await GitProcess.exec(['mv', 'foo', 'bar'], repo);

        const status = await getStatusOrThrow(repo);
        const files = status.workingDirectory.files;

        expect(files).to.have.lengthOf(1);
        const file = files[0];
        expect(file.path).to.equal('bar');
        expect(file.status).to.include({
          kind: AppFileStatusKind.Renamed,
          oldPath: 'foo',
        });
      });

      it('reflects copies', async () => {
        const repo = await setupFixtureRepository('copy-detection-status');

        // Git 2.18 now uses a new config value to handle detecting copies, so
        // users who have this enabled will see this. For reference,
        // dodes not enable this by default.
        await setupLocalConfig(repo, [['status.renames', 'copies']]);

        await GitProcess.exec(['add', '.'], repo);

        const status = await getStatusOrThrow(repo);
        const files = status.workingDirectory.files;

        expect(files).to.have.lengthOf(2);
        const file = files[0];
        expect(file.status.kind).to.equal(AppFileStatusKind.Modified);
        expect(file.path).to.equal('CONTRIBUTING.md');
        expect(files[1].path).to.equal('docs/OVERVIEW.md');
        expect(files[1].status).to.include({
          kind: AppFileStatusKind.Copied,
          oldPath: 'CONTRIBUTING.md',
        });
      });

      it('returns null for directory without a .git directory', async () => {
        repoPath = setupEmptyDirectory();
        const status = await getStatus(repoPath);
        expect(status).to.equal(null);
      });
    });

    describe('with submodules', () => {
      it('returns the submodules status', async () => {
        const repoPath = await setupFixtureRepository('submodule-basic-setup');
        const submodulePath = path.join(repoPath, 'foo', 'submodule');

        const checkSubmoduleChanges = async (changes: {
          modifiedChanges: boolean;
          untrackedChanges: boolean;
          commitChanged: boolean;
        }) => {
          const status = await getStatusOrThrow(repoPath);
          const files = status.workingDirectory.files;
          expect(files).to.have.lengthOf(1);

          const file = files[0];
          expect(file.path).to.equal('foo/submodule');
          expect(file.status.kind).to.equal(AppFileStatusKind.Modified);
          expect(file.status.submoduleStatus?.modifiedChanges).to.equal(changes.modifiedChanges);
          expect(file.status.submoduleStatus?.untrackedChanges).to.equal(changes.untrackedChanges);
          expect(file.status.submoduleStatus?.commitChanged).to.equal(changes.commitChanged);
        };

        // Modify README.md file. Now the submodule has modified changes.
        await FSE.writeFile(path.join(submodulePath, 'README.md'), 'Hello world\n');
        await checkSubmoduleChanges({ modifiedChanges: true, untrackedChanges: false, commitChanged: false });

        // Create untracked file in submodule. Now the submodule has both
        // modified and untracked changes.
        await FSE.writeFile(path.join(submodulePath, 'test'), 'test\n');
        await checkSubmoduleChanges({
          modifiedChanges: true,
          untrackedChanges: true,
          commitChanged: false,
        });

        // Commit the changes within the submodule. Now the submodule has commit changes.
        await GitProcess.exec(['add', '.'], submodulePath);
        await GitProcess.exec(['commit', '-m', 'changes'], submodulePath);
        await checkSubmoduleChanges({
          modifiedChanges: false,
          untrackedChanges: false,
          commitChanged: true,
        });
      });
    });
  });
});
