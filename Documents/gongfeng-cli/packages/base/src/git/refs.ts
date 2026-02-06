import { git } from './core';

/**
 * Format a local branch in the ref syntax, ensuring situations when the branch
 * is ambiguous are handled.
 *
 * Examples:
 *  - master -> refs/heads/master
 *  - heads/cli/master -> refs/heads/cli/master
 *
 * @param name The local branch name
 */
export function formatAsLocalRef(name: string): string {
  if (name.startsWith('heads/')) {
    // In some cases, Git will report this name explicitly to distinguish from
    // a remote ref with the same name - this ensures we format it correctly.
    return `refs/${name}`;
  }
  if (!name.startsWith('refs/heads/')) {
    // By default Git will drop the heads prefix unless absolutely necessary
    // - include this to ensure the ref is fully qualified.
    return `refs/heads/${name}`;
  }
  return name;
}

/**
 * Read a symbolic ref from the repository.
 *
 * Symbolic refs are used to point to other refs, similar to how symlinks work
 * for files. Because refs can be removed easily from a Git repository,
 * symbolic refs should only be used when absolutely necessary.
 *
 * @param repoPath The repository path to lookup
 * @param ref The symbolic ref to resolve
 *
 * @returns the canonical ref, if found, or `null` if `ref` cannot be found or
 *          is not a symbolic ref
 */
export async function getSymbolicRef(repoPath: string, ref: string): Promise<string | null> {
  const result = await git(['symbolic-ref', '-q', ref], repoPath, 'getSymbolicRef', {
    //  - 1 is the exit code that Git throws in quiet mode when the ref is not a
    //    symbolic ref
    //  - 128 is the generic error code that Git returns when it can't find
    //    something
    successExitCodes: new Set([0, 1, 128]),
  });

  if (result.exitCode === 1 || result.exitCode === 128) {
    return null;
  }

  return result.stdout.trim();
}

/**
 * Get current branch of the git repository
 *
 * @param repoPath The repository path to lookup
 *
 * @returns the branch name, if found, or `null` if `ref` cannot be found
 */
export async function getCurrentBranch(repoPath: string): Promise<string | null> {
  const headRef = await getSymbolicRef(repoPath, 'HEAD');
  if (headRef) {
    return headRef.replace(/^(refs\/heads\/)/, '');
  }
  return null;
}

/**
 * get the hash of the ref from the repository.
 *
 * Displays references available in a local repository along with the associated commit IDs.
 * Results can be filtered using a pattern and tags can be dereferenced into object IDs.
 * Additionally, it can be used to test whether a particular ref exists.
 *
 * @param repoPath The repository path to lookup
 * @param ref The ref to resolve
 *
 * @returns the canonical hash and ref, if found, or `null` if `ref` cannot be found
 */
export async function getRefSha(repoPath: string, ref: string): Promise<string | null> {
  const result = await git(['show-ref', '--verify', '--', ref], repoPath, 'getRefs', {
    //  - 128 is the generic error code that Git returns when it can't find
    //    something
    successExitCodes: new Set([0, 128]),
  });
  if (result.exitCode === 128) {
    return null;
  }
  return result.stdout.trim();
}
