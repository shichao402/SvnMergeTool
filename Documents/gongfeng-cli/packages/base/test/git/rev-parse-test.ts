import * as path from 'path';
import * as FSE from 'fs-extra';
import * as os from 'os';
import { writeFile } from 'fs-extra';

import { setupEmptyRepository, setupFixtureRepository } from '../helpers/repositories';
import { getPathFromRepoRoot, getRepositoryType } from '../../src/git/rev-parse';
import { expect } from 'chai';
import { mkdirSync } from '../helpers/temp';
import { git } from '../../src/git/core';
import { GitProcess } from '@tencent/code-dugite';

describe('git/rev-parse', () => {
  let repoPath: string;

  beforeEach(async () => {
    repoPath = await setupFixtureRepository('test-repo');
  });

  describe('getPathFromRepoRoot', async () => {
    it('returns the relative path from repository root', async () => {
      const packages = path.join(repoPath, 'packages');
      await FSE.mkdir(packages);
      expect(await getPathFromRepoRoot(packages)).to.equal('packages/');
    });

    it('returns relative path from git repository root', async () => {
      expect(await getPathFromRepoRoot(repoPath)).to.equal('');
    });
  });

  describe('getRepositoryType', () => {
    it('should return an absolute path when run inside a working directory', async () => {
      const result = await getRepositoryType(repoPath);
      expect(result).to.deep.equal({
        kind: 'regular',
        topLevelWorkingDirectory: repoPath,
      });

      const subdirPath = path.join(repoPath, 'subdir');
      await FSE.mkdir(subdirPath);

      const subResult = await getRepositoryType(subdirPath);
      expect(subResult).to.deep.equal({
        kind: 'regular',
        topLevelWorkingDirectory: repoPath,
      });
    });

    it('should return missing when not run inside a working directory', async () => {
      expect(await getRepositoryType(os.tmpdir())).to.deep.equal({
        kind: 'missing',
      });
    });

    it('should return correct path from submodules', async () => {
      const fixturePath = mkdirSync('get-top-level-working-directory-test-');

      const firstRepoPath = path.join(fixturePath, 'repo1');
      const secondRepoPath = path.join(fixturePath, 'repo2');

      await git(['init', 'repo1'], fixturePath, '');
      await git(['init', 'repo2'], fixturePath, '');

      await git(['commit', '--allow-empty', '-m', 'Initial commit'], secondRepoPath, '');
      await git([...['-c', 'protocol.file.allow=always'], ...['submodule', 'add', '../repo2']], firstRepoPath, '');

      expect(await getRepositoryType(firstRepoPath)).to.deep.equal({
        kind: 'regular',
        topLevelWorkingDirectory: firstRepoPath,
      });

      const subModulePath = path.join(firstRepoPath, 'repo2');
      expect(await getRepositoryType(subModulePath)).to.deep.equal({
        kind: 'regular',
        topLevelWorkingDirectory: subModulePath,
      });
    });

    it('returns regular for default initialized repository', async () => {
      const repoPath = await setupEmptyRepository();
      expect(await getRepositoryType(repoPath)).to.deep.equal({
        kind: 'regular',
        topLevelWorkingDirectory: repoPath,
      });
    });

    it('returns bar for initialized bare repository', async () => {
      const path = mkdirSync('no-repository-here');
      await GitProcess.exec(['init', '--bare'], path);
      expect(await getRepositoryType(path)).to.deep.equal({
        kind: 'bare',
      });
    });

    it('returns missing for empty directory', async () => {
      const p = mkdirSync('no-actual-repository-here');
      expect(await getRepositoryType(p)).to.deep.equal({
        kind: 'missing',
      });
    });

    it('returns missing for missing directory', async () => {
      const p = mkdirSync('no-actual-repository-here');
      const missingPath = path.join(p, 'missing-folder');

      expect(await getRepositoryType(missingPath)).to.deep.equal({
        kind: 'missing',
      });
    });

    it('returns unsafe for unsafe repository', async () => {
      const previousHomeValue = process.env.HOME;

      // Creating a stub global config so we can unset safe.directory config
      // which will supersede any system config that might set * to ignore
      // warnings about a different owner
      //
      // This is because safe.directory setting is ignored if found in local
      // config, environment variables or command line arguments.
      const testHomeDirectory = mkdirSync('test-home-directory');
      const gitConfigPath = path.join(testHomeDirectory, '.gitconfig');
      await writeFile(
        gitConfigPath,
        `[safe]
directory=`,
      );

      process.env.HOME = testHomeDirectory;
      process.env.GIT_TEST_ASSUME_DIFFERENT_OWNER = '1';

      const result = await getRepositoryType(repoPath);
      expect(result.kind).to.equal('unsafe');

      process.env.GIT_TEST_ASSUME_DIFFERENT_OWNER = undefined;
      process.env.HOME = previousHomeValue;
    });
  });
});
