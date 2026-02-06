import { IPullProgress } from '../models/progress';
import { getConfigValue } from './config';
import { Remote } from '../models/remote';
import { git, GitError, IGitExecutionOptions } from './core';
import { AuthenticationErrors } from './authentication';
import { executionOptionsWithProgress } from '../progress/from-process';
import { PullProgressParser } from '../progress/pull';

/**
 * Defaults the pull default for divergent paths to try to fast forward and if
 * not perform a merge. Aka uses the flag --ff
 *
 * It checks whether the user has a config set for this already, if so, no need for
 * default.
 */
async function getDefaultPullDivergentBranchArguments(repoPath: string): Promise<ReadonlyArray<string>> {
  try {
    const pullFF = await getConfigValue(repoPath, 'pull.ff');
    return pullFF !== null ? [] : ['--ff'];
  } catch (e) {
    // console.error("Couldn't read 'pull.ff' config", e);
  }

  // If there is a failure in checking the config, we still want to use any
  // config and not overwrite the user's set config behavior. This will show the
  // git error if no config is set.
  return [];
}

async function getPullArgs(
  repoPath: string,
  remote: string,
  enableRecurseSubmodules: boolean,
  progressCallback?: (progress: IPullProgress) => void,
) {
  const divergentPathArgs = await getDefaultPullDivergentBranchArguments(repoPath);

  const args = ['pull', ...divergentPathArgs];

  if (enableRecurseSubmodules) {
    args.push('--recurse-submodules');
  }

  if (progressCallback !== null) {
    args.push('--progress');
  }

  args.push(remote);

  return args;
}

/**
 * Pull from the specified remote.
 *
 * @param repoPath - The repository in which the pull should take place
 *
 * @param remote     - The name of the remote that should be pulled from
 *
 * @param enableRecurseSubmodules   - Whether enable submodules
 *
 * @param progressCallback - An optional function which will be invoked
 *                           with information about the current progress
 *                           of the pull operation. When provided this enables
 *                           the '--progress' command line flag for
 *                           'git pull'.
 */
export async function pull(
  repoPath: string,
  remote: Remote,
  enableRecurseSubmodules: boolean,
  progressCallback?: (progress: IPullProgress) => void,
): Promise<void> {
  let opts: IGitExecutionOptions = {
    expectedErrors: AuthenticationErrors,
  };

  if (progressCallback) {
    const title = `Pulling ${remote.name}`;
    const kind = 'pull';

    opts = await executionOptionsWithProgress(
      { ...opts, trackLFSProgress: true },
      new PullProgressParser(),
      (progress) => {
        // In addition to progress output from the remote end and from
        // git itself, the stderr output from pull contains information
        // about ref updates. We don't need to bring those into the progress
        // stream so we'll just punt on anything we don't know about for now.
        if (progress.kind === 'context') {
          if (!progress.text.startsWith('remote: Counting objects')) {
            return;
          }
        }

        const description = progress.kind === 'progress' ? progress.details.text : progress.text;

        const value = progress.percent;

        progressCallback({
          kind,
          title,
          description,
          value,
          remote: remote.name,
        });
      },
    );

    // Initial progress
    progressCallback({ kind, title, value: 0, remote: remote.name });
  }

  const args = await getPullArgs(repoPath, remote.name, enableRecurseSubmodules, progressCallback);
  const result = await git(args, repoPath, 'pull', opts);

  if (result.gitErrorDescription) {
    throw new GitError(result, args);
  }
}
