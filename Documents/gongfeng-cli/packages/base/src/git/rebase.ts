import { RebaseInternalState } from '../models/rebase';
import { pathExists } from '../utils/path-exists';
import * as Path from 'path';
import { readFile } from 'fs/promises';

/**
 * Check the `.git/REBASE_HEAD` file exists in a repository to confirm
 * a rebase operation is underway.
 */
function isRebaseHeadSet(repoPath: string) {
  const path = Path.join(repoPath, '.git', 'REBASE_HEAD');
  return pathExists(path);
}

/**
 * Get the internal state about the rebase being performed on a repository. This
 * information is required to help Desktop display information to the user
 * about the current action as well as the options available.
 *
 * Returns `null` if no rebase is detected, or if the expected information
 * cannot be found in the repository.
 */
export async function getRebaseInternalState(repoPath: string): Promise<RebaseInternalState | null> {
  const isRebase = await isRebaseHeadSet(repoPath);

  if (!isRebase) {
    return null;
  }

  let originalBranchTip: string | null = null;
  let targetBranch: string | null = null;
  let baseBranchTip: string | null = null;

  try {
    originalBranchTip = await readFile(Path.join(repoPath, '.git', 'rebase-merge', 'orig-head'), 'utf8');

    originalBranchTip = originalBranchTip.trim();

    targetBranch = await readFile(Path.join(repoPath, '.git', 'rebase-merge', 'head-name'), 'utf8');

    if (targetBranch.startsWith('refs/heads/')) {
      targetBranch = targetBranch.substring(11).trim();
    }

    baseBranchTip = await readFile(Path.join(repoPath, '.git', 'rebase-merge', 'onto'), 'utf8');

    baseBranchTip = baseBranchTip.trim();
  } catch {}

  if (originalBranchTip != null && targetBranch != null && baseBranchTip != null) {
    return { originalBranchTip, targetBranch, baseBranchTip };
  }

  // unable to resolve the rebase state of this repository

  return null;
}
