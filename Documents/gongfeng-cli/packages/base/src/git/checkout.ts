import { git, IGitExecutionOptions } from './core';
import { Branch, BranchType, ICheckoutProgress } from '../models';
import { CheckoutProgressParser, executionOptionsWithProgress } from '../progress';
import { AuthenticationErrors } from './authentication';

export type ProgressCallback = (progress: ICheckoutProgress) => void;

async function getCheckoutArgs(
  repoPath: string,
  branch: Branch,
  enableRecurseSubmodules: boolean,
  progressCallback?: ProgressCallback,
) {
  const baseArgs = progressCallback !== null ? ['checkout', '--progress'] : ['checkout'];

  if (enableRecurseSubmodules) {
    return branch.type === BranchType.Remote
      ? baseArgs.concat(branch.name, '-b', branch.nameWithoutRemote, '--recurse-submodules', '--')
      : baseArgs.concat(branch.name, '--recurse-submodules', '--');
  }
  return branch.type === BranchType.Remote
    ? baseArgs.concat(branch.name, '-b', branch.nameWithoutRemote, '--')
    : baseArgs.concat(branch.name, '--');
}

/**
 * Check out the given branch.
 *
 * @param repoPath - The repository path in which the branch checkout should
 *                     take place
 *
 * @param branch     - The branch name that should be checked out
 *
 * @param enableRecurseSubmodules   - Whether enable submodules
 *
 * @param progressCallback - An optional function which will be invoked
 *                           with information about the current progress
 *                           of the checkout operation. When provided this
 *                           enables the '--progress' command line flag for
 *                           'git checkout'.
 */
export async function checkoutBranch(
  repoPath: string,
  branch: Branch,
  enableRecurseSubmodules: boolean,
  progressCallback?: ProgressCallback,
): Promise<true> {
  let opts: IGitExecutionOptions = {
    expectedErrors: AuthenticationErrors,
  };

  if (progressCallback) {
    const title = `Checking out branch ${branch.name}`;
    const kind = 'checkout';
    const targetBranch = branch.name;

    opts = await executionOptionsWithProgress(
      { ...opts, trackLFSProgress: true },
      new CheckoutProgressParser(),
      (progress) => {
        if (progress.kind === 'progress') {
          const description = progress.details.text;
          const value = progress.percent;

          progressCallback({ kind, title, description, value, targetBranch });
        }
      },
    );

    // Initial progress
    progressCallback({ kind, title, value: 0, targetBranch });
  }

  const args = await getCheckoutArgs(repoPath, branch, enableRecurseSubmodules, progressCallback);

  await git(args, repoPath, 'checkoutBranch', opts);

  // we return `true` here so `GitStore.performFailableGitOperation`
  // will return _something_ differentiable from `undefined` if this succeeds
  return true;
}

/** Check out the paths at HEAD. */
export async function checkoutPaths(repoPath: string, paths: ReadonlyArray<string>): Promise<void> {
  await git(['checkout', 'HEAD', '--', ...paths], repoPath, 'checkoutPaths');
}
