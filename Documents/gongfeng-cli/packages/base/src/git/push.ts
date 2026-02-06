import { GitError as DugiteError } from '@tencent/code-dugite';
import { Remote } from '../models/remote';
import { IPushProgress } from '../models/progress';
import { git, GitError, IGitExecutionOptions } from './core';
import { AuthenticationErrors } from './authentication';
import { PushProgressParser } from '../progress';
import { executionOptionsWithProgress } from '../progress/from-process';

export type PushOptions = {
  /**
   * Force-push the branch without losing changes in the remote that
   * haven't been fetched.
   *
   * See https://git-scm.com/docs/git-push#Documentation/git-push.txt---no-force-with-lease
   */
  readonly forceWithLease: boolean;
};

/**
 * Push from the remote to the branch, optionally setting the upstream.
 *
 * @param repoPath - The repository path from which to push
 *
 * @param remote - The remote to push the specified branch to
 *
 * @param localBranch - The local branch to push
 *
 * @param remoteBranch - The remote branch to push to
 *
 * @param tagsToPush - The tags to push along with the branch.
 *
 * @param options - Optional customizations for the push execution.
 *                  see PushOptions for more information.
 *
 * @param progressCallback - An optional function which will be invoked
 *                           with information about the current progress
 *                           of the push operation. When provided this enables
 *                           the '--progress' command line flag for
 *                           'git push'.
 */
export async function push(
  repoPath: string,
  remote: Remote,
  localBranch: string,
  remoteBranch: string | null,
  tagsToPush: ReadonlyArray<string> | null,
  options: PushOptions = {
    forceWithLease: false,
  },
  progressCallback?: (progress: IPushProgress) => void,
): Promise<void> {
  const args = ['push', remote.name, remoteBranch ? `${localBranch}:${remoteBranch}` : localBranch];

  if (tagsToPush !== null) {
    args.push(...tagsToPush);
  }
  if (!remoteBranch) {
    args.push('--set-upstream');
  } else if (options.forceWithLease) {
    args.push('--force-with-lease');
  }

  const expectedErrors = new Set<DugiteError>(AuthenticationErrors);
  expectedErrors.add(DugiteError.ProtectedBranchForcePush);

  let opts: IGitExecutionOptions = {
    expectedErrors,
  };

  if (progressCallback) {
    args.push('--progress');
    const title = `Pushing to ${remote.name}`;
    const kind = 'push';

    opts = await executionOptionsWithProgress(
      { ...opts, trackLFSProgress: true },
      new PushProgressParser(),
      (progress) => {
        const description = progress.kind === 'progress' ? progress.details.text : progress.text;
        const value = progress.percent;

        progressCallback({
          kind,
          title,
          description,
          value,
          remote: remote.name,
          branch: localBranch,
        });
      },
    );

    // Initial progress
    progressCallback({
      kind: 'push',
      title,
      value: 0,
      remote: remote.name,
      branch: localBranch,
    });
  }

  const result = await git(args, repoPath, 'push', opts);

  if (result.gitErrorDescription) {
    throw new GitError(result, args);
  }
}

export async function push2(
  repoPath: string,
  remote: Remote,
  remoteUrl: string,
  localBranch: string,
  remoteBranch: string | null,
  tagsToPush: ReadonlyArray<string> | null,
  options: PushOptions = {
    forceWithLease: false,
  },
  progressCallback?: (progress: IPushProgress) => void,
): Promise<void> {
  const args = ['push', remoteUrl, remoteBranch ? `${localBranch}:${remoteBranch}` : localBranch];

  if (tagsToPush !== null) {
    args.push(...tagsToPush);
  }
  if (!remoteBranch) {
    args.push('--set-upstream');
  } else if (options.forceWithLease) {
    args.push('--force-with-lease');
  }

  const expectedErrors = new Set<DugiteError>(AuthenticationErrors);
  expectedErrors.add(DugiteError.ProtectedBranchForcePush);

  let opts: IGitExecutionOptions = {
    expectedErrors,
  };

  if (progressCallback) {
    args.push('--progress');
    const title = `Pushing to ${remote.name}`;
    const kind = 'push';

    opts = await executionOptionsWithProgress(
      { ...opts, trackLFSProgress: true },
      new PushProgressParser(),
      (progress) => {
        const description = progress.kind === 'progress' ? progress.details.text : progress.text;
        const value = progress.percent;

        progressCallback({
          kind,
          title,
          description,
          value,
          remote: remote.name,
          branch: localBranch,
        });
      },
    );

    // Initial progress
    progressCallback({
      kind: 'push',
      title,
      value: 0,
      remote: remote.name,
      branch: localBranch,
    });
  }

  const result = await git(args, repoPath, 'push', opts);

  if (result.gitErrorDescription) {
    throw new GitError(result, args);
  }
}
