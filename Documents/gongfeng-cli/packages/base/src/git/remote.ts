import { git } from './core';
import { GitError } from '@tencent/code-dugite';
import * as gitUrlParse from 'git-url-parse';
import { Remote } from '../models/remote';
import { getConfigValue } from './config';
import { getSymbolicRef } from './refs';

const remoteReg = /(.+)\s+(.+)\s+\((push|fetch)\)/;

/**
 * List the remotes
 */
export async function getRemotes(repoPath: string): Promise<Remote[]> {
  const result = await git(['remote', '-v'], repoPath, 'getRemotes', {
    expectedErrors: new Set([GitError.NotAGitRepository]),
  });

  if (result.gitError === GitError.NotAGitRepository) {
    return [];
  }

  const output = result.stdout;
  const lines = output.split('\n');
  return parseRemotes(lines);
}

/**
 *
 * @param repoPath the path of repository
 */
export async function getResolvedRemotes(repoPath: string): Promise<Remote[]> {
  const remotes = await getRemotes(repoPath);
  const values = await getConfigValue(repoPath, ['--get-regexp', '^remote\\..*\\.gf-resolved$']);
  if (values?.length) {
    values.forEach((value) => {
      const parts = value.split('\n');
      if (parts.length < 2) {
        return;
      }
      const rp = parts[0].split('.');
      if (rp.length < 2) {
        return;
      }
      const name = rp[1];
      remotes.forEach((remote) => {
        if (remote.name === name) {
          remote.resolved = parts[1];
        }
      });
    });
  }
  return remotes;
}

function parseRemotes(gitRemotes: string[]): Remote[] {
  const remotes: Remote[] = [];
  gitRemotes.forEach((remote) => {
    if (!remoteReg.test(remote)) {
      return;
    }
    const matches = remote.match(remoteReg);
    if (!matches || matches?.length < 4) {
      return;
    }
    const name = matches[1].trim();
    const urlStr = matches[2].trim();
    const urlType = matches[3].trim();

    try {
      let r = remotes.find((ro) => ro.name === name);
      if (!r) {
        r = {
          name,
        };
        remotes.push(r);
      }
      const url = gitUrlParse(urlStr);
      if (urlType === 'fetch') {
        r.fetchUrl = url;
      }
      if (urlType === 'push') {
        r.pushUrl = url;
      }
    } catch (e) {}
  });
  return remotes;
}

/** Add a new remote with the given URL. */
export async function addRemote(repoPath: string, name: string, url: string): Promise<Remote> {
  await git(['remote', 'add', name, url], repoPath, 'addRemote');

  return {
    name,
    fetchUrl: gitUrlParse(url),
    pushUrl: gitUrlParse(url),
  };
}

/** Removes an existing remote, or silently errors if it doesn't exist */
export async function removeRemote(repoPath: string, name: string): Promise<void> {
  const options = {
    successExitCodes: new Set([0, 2, 128]),
  };

  await git(['remote', 'remove', name], repoPath, 'removeRemote', options);
}

/** Changes the URL for the remote that matches the given name  */
export async function setRemoteURL(repoPath: string, name: string, url: string): Promise<true> {
  await git(['remote', 'set-url', name, url], repoPath, 'setRemoteURL');
  return true;
}

/**
 * Get the URL for the remote that matches the given name.
 *
 * Returns null if the remote could not be found
 */
export async function getRemoteURL(repoPath: string, name: string): Promise<string | null> {
  const result = await git(['remote', 'get-url', name], repoPath, 'getRemoteURL', {
    successExitCodes: new Set([0, 2, 128]),
  });

  if (result.exitCode !== 0) {
    return null;
  }

  return result.stdout;
}

export async function getRemoteHEAD(repoPath: string, remote: string): Promise<string | null> {
  const remoteNamespace = `refs/remotes/${remote}/`;
  const match = await getSymbolicRef(repoPath, `${remoteNamespace}HEAD`);
  if (match !== null && match.length > remoteNamespace.length && match.startsWith(remoteNamespace)) {
    // strip out everything related to the remote because this
    // is likely to be a tracked branch locally
    // e.g. `master`, `develop`, etc
    return match.substring(remoteNamespace.length);
  }

  return null;
}

/**
 * Attempt to find the remote which we consider to be the "default"
 * remote, i.e. in most cases the 'origin' remote.
 *
 * If no remotes are given this method will return null, if no "default"
 * branch could be found the first remote is considered the default.
 *
 * @param remotes A list of remotes for a given repository
 */
export function findDefaultRemote(remotes: ReadonlyArray<Remote>): Remote | null {
  return remotes.find((x) => x.name === 'origin') || remotes[0] || null;
}

/**
 * Attempt to find gongfeng project full path from remote URL
 * @param repoPath - The repository in which the pull should take place
 * @param name - The repository remote name
 */
export async function projectPathFromRemote(repoPath: string, name?: string) {
  const remotes = await getRemotes(repoPath);
  if (!remotes?.length) {
    return null;
  }
  let remote: Remote | undefined | null;
  if (name) {
    remote = remotes.find((r) => r.name === name);
  } else {
    remote = findDefaultRemote(remotes);
  }
  if (!remote) {
    return null;
  }
  return `${remote.fetchUrl?.owner}/${remote.fetchUrl?.name}`;
}

/**
 * Attempt to find git remote from gongfeng project full path
 * @param repoPath - The repository in which the pull should take place
 * @param projectPath - The project full path of gongfeng project
 */
export async function findRemoteByProjectPath(repoPath: string, projectPath: string): Promise<Remote | null> {
  const remotes = await getRemotes(repoPath);
  if (!remotes?.length) {
    return null;
  }
  const remote = remotes.find((remote) => {
    const remoteProjectPath = `${remote.fetchUrl?.owner}/${remote.fetchUrl?.name}`;
    return remoteProjectPath === projectPath;
  });
  if (!remote) {
    return null;
  }
  return remote;
}
