import color from './color';
import { prompt } from 'inquirer';
import { Remote } from './models';
import { git } from './index';

export async function getCurrentRemote(repoPath: string): Promise<Remote | undefined> {
  const remotes = await git.getRemotes(repoPath);
  if (!remotes?.length) {
    console.log(color.error('remote not found!'));
    return;
  }
  const remote = remotes.find((r) => r.resolved === 'target');
  if (remote) {
    return remote;
  }
  if (remotes.length === 1) {
    return remotes[0];
  }
  const choices: string[] = [];
  remotes.forEach((remote: Remote) => {
    choices.push(`${remote.name}:${remote.pushUrl?.href}`);
  });
  const selected = await prompt([
    {
      type: 'rawlist',
      name: 'remote',
      message: 'Which should be the current project remote for this directory',
      choices,
      default: 0,
    },
  ]);
  const selectedRemote = remotes.find((remote: Remote) => {
    return selected.remote === `${remote.name}:${remote.pushUrl?.href}`;
  });
  if (selectedRemote) {
    await git.setConfigValue(repoPath, `remote.${selectedRemote.name}.gf-resolved`, 'target');
  }
  return selectedRemote;
}

export async function getSourceRemote(repoPath: string): Promise<Remote | undefined> {
  const remotes = await git.getRemotes(repoPath);
  if (!remotes?.length) {
    console.log(color.error('remote not found!'));
    return;
  }
  if (remotes.length === 1) {
    return remotes[0];
  }
  const choices: string[] = [];
  remotes.forEach((remote: Remote) => {
    choices.push(`${remote.name}:${remote.pushUrl?.href}`);
  });
  const selected = await prompt([
    {
      type: 'rawlist',
      name: 'remote',
      message: 'Which should be the source remote for this directory',
      choices,
      default: 0,
    },
  ]);
  return remotes.find((remote: Remote) => {
    return selected.remote === `${remote.name}:${remote.pushUrl?.href}`;
  });
}
