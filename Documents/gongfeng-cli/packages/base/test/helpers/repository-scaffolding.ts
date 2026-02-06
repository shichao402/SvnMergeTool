import * as FSE from 'fs-extra';
import * as Path from 'path';
import { GitProcess } from '@tencent/code-dugite';

type TreeEntry = {
  /** The relative path of the file in the repository */
  readonly path: string;
  /**
   * The contents associated with the current path.
   *
   * Use `null` to remove the file from the working directory before committing
   */
  readonly contents: Buffer | string | null;
};

type Tree = {
  readonly entries: ReadonlyArray<TreeEntry>;
  /**
   * Optional commit message to pass to Git.
   *
   * If undefined, `'commit'` will be used.
   */
  readonly commitMessage?: string;
};

/**
 * Make a commit tot he repository by creating the specified files in the
 * working directory, staging all changes, and then committing with the
 * specified message.
 */
export async function makeCommit(repository: string, tree: Tree) {
  for (const entry of tree.entries) {
    const fullPath = Path.join(repository, entry.path);
    if (entry.contents === null) {
      await GitProcess.exec(['rm', entry.path], repository);
    } else {
      await FSE.writeFile(fullPath, entry.contents);
      await GitProcess.exec(['add', entry.path], repository);
    }
  }

  const message = tree.commitMessage || 'commit';
  await GitProcess.exec(['commit', '-m', message], repository);
}

export async function switchTo(repoPath: string, branch: string) {
  const result = await GitProcess.exec(['rev-parse', '--verify', branch], repoPath);

  if (result.exitCode === 128) {
    // ref does not exists, checkout and create the branch
    await GitProcess.exec(['checkout', '-b', branch], repoPath);
  } else {
    // just switch to the branch
    await GitProcess.exec(['checkout', branch], repoPath);
  }
}
