import { spawnAndComplete } from './spawn';
import { getCaptures } from '../utils/regex';

/**
 * List the modified binary files' paths in the given repository
 *
 * @param repoPath to run git operation in
 * @param ref ref (sha, branch, etc) to compare the working index against
 *
 * if you're mid-merge pass `'MERGE_HEAD'` to ref to get a diff of `HEAD` vs `MERGE_HEAD`,
 * otherwise you should probably pass `'HEAD'` to get a diff of the working tree vs `HEAD`
 */
export async function getBinaryPaths(repoPath: string, ref: string): Promise<ReadonlyArray<string>> {
  const { output } = await spawnAndComplete(['diff', '--numstat', '-z', ref], repoPath, 'getBinaryPaths');
  const captures = getCaptures(output.toString('utf8'), binaryListRegex);
  if (captures.length === 0) {
    return [];
  }
  // flatten the list (only does one level deep)
  const flatCaptures = captures.reduce((acc, val) => acc.concat(val));
  return flatCaptures;
}

const binaryListRegex = /-\t-\t(?:\0.+\0)?([^\0]*)/gi;
