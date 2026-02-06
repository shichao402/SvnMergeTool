import * as Path from 'path';
import { pathExists } from '../utils/path-exists';

/**
 * Check the `.git/MERGE_HEAD` file exists in a repository to confirm
 * that it is in a conflicted state.
 */
export async function isMergeHeadSet(repoPath: string): Promise<boolean> {
  const path = Path.join(repoPath, '.git', 'MERGE_HEAD');
  return await pathExists(path);
}

/**
 * Check the `.git/SQUASH_MSG` file exists in a repository
 * This would indicate we did a merge --squash and have not committed.. indicating
 * we have detected a conflict.
 *
 * Note: If we abort the merge, this doesn't get cleared automatically which
 * could lead to this being erroneously available in a non merge --squashing scenario.
 */
export async function isSquashMsgSet(repoPath: string): Promise<boolean> {
  const path = Path.join(repoPath, '.git', 'SQUASH_MSG');
  return await pathExists(path);
}
