import * as Path from 'path';
import * as FSE from 'fs-extra';
import * as klawSync from 'klaw-sync';
import { Item } from 'klaw-sync';
import { mkdirSync } from './temp';

/**
 * Initialize a new, empty folder that is incorrectly associated with a Git
 * repository. This should only be used to test error handling of the Git
 * interactions.
 */
export function setupEmptyDirectory(): string {
  return mkdirSync('no-repository-here');
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
