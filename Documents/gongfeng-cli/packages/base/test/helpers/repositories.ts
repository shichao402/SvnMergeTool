import * as Path from 'path';
import * as FSE from 'fs-extra';
import { mkdirSync } from './temp';
import * as klawSync from 'klaw-sync';
import { Item } from 'klaw-sync';
import { GitProcess } from '@tencent/code-dugite';
import { makeCommit, switchTo } from './repository-scaffolding';

/**
 * Initialize a new, empty folder that is incorrectly associated with a Git
 * repository. This should only be used to test error handling of the Git
 * interactions.
 */
export function setupEmptyDirectory(): string {
  return mkdirSync('no-repository-here');
}

/**
 * Initializes a new, empty, git repository at in a temporary location.
 *
 * @returns the new local repository
 */
export async function setupEmptyRepository(): Promise<string> {
  const repoPath = mkdirSync('cli-empty-repo-');
  await GitProcess.exec(['init'], repoPath);

  return repoPath;
}

/**
 * Set up the named fixture repository to be used in a test.
 *
 * @returns The path to the set up fixture repository.
 */
export async function setupFixtureRepository(repositoryName: string): Promise<string> {
  const testRepoFixturePath = Path.join(__dirname, '..', 'fixtures', repositoryName);
  const testRepoPath = mkdirSync('cli-git-test-');
  await FSE.copy(testRepoFixturePath, testRepoPath);

  await FSE.rename(Path.join(testRepoPath, '_git'), Path.join(testRepoPath, '.git'));

  const ignoreHiddenFiles = function (item: Item) {
    const basename = Path.basename(item.path);
    return basename === '.' || basename[0] !== '.';
  };

  const entries = klawSync(testRepoPath);
  const visiblePaths = entries.filter(ignoreHiddenFiles);
  const submodules = visiblePaths.filter((entry) => Path.basename(entry.path) === '_git');

  for (const submodule of submodules) {
    const directory = Path.dirname(submodule.path);
    const newPath = Path.join(directory, '.git');
    await FSE.rename(submodule.path, newPath);
  }

  return testRepoPath;
}

/**
 * Setup a repository and create a merge conflict
 *
 * @returns the new local repository path
 *
 * The current branch will be 'other-branch' and the merged branch will be
 * 'master' in your test harness.
 *
 * The conflicted file will be 'foo'.
 */
export async function setupConflictedRepo(): Promise<string> {
  const repo = await setupEmptyRepository();

  const firstCommit = {
    entries: [{ path: 'foo', contents: '' }],
  };

  await makeCommit(repo, firstCommit);

  // create this branch starting from the first commit, but don't checkout it
  // because we want to create a divergent history
  await GitProcess.exec(['branch', 'other-branch'], repo);

  const secondCommit = {
    entries: [{ path: 'foo', contents: 'b1' }],
  };

  await makeCommit(repo, secondCommit);

  await switchTo(repo, 'other-branch');

  const thirdCommit = {
    entries: [{ path: 'foo', contents: 'b2' }],
  };
  await makeCommit(repo, thirdCommit);

  await GitProcess.exec(['merge', 'master'], repo);

  return repo;
}

/**
 * Setup a repository and create a merge conflict with multiple files
 *
 * @returns the new local repository
 *
 * The current branch will be 'other-branch' and the merged branch will be
 * 'master' in your test harness.
 *
 * The conflicted files will be 'foo', 'bar', and 'baz'.
 */
export async function setupConflictedRepoWithMultipleFiles(): Promise<string> {
  const repo = await setupEmptyRepository();

  const firstCommit = {
    entries: [
      { path: 'foo', contents: 'b0' },
      { path: 'bar', contents: 'b0' },
    ],
  };

  await makeCommit(repo, firstCommit);

  // create this branch starting from the first commit, but don't checkout it
  // because we want to create a divergent history
  await GitProcess.exec(['branch', 'other-branch'], repo);

  const secondCommit = {
    entries: [
      { path: 'foo', contents: 'b1' },
      { path: 'bar', contents: null },
      { path: 'baz', contents: 'b1' },
      { path: 'cat', contents: 'b1' },
    ],
  };

  await makeCommit(repo, secondCommit);

  await switchTo(repo, 'other-branch');

  const thirdCommit = {
    entries: [
      { path: 'foo', contents: 'b2' },
      { path: 'bar', contents: 'b2' },
      { path: 'baz', contents: 'b2' },
      { path: 'cat', contents: 'b2' },
    ],
  };

  await makeCommit(repo, thirdCommit);

  await FSE.writeFile(Path.join(repo, 'dog'), 'touch');

  await GitProcess.exec(['merge', 'master'], repo);

  return repo;
}
