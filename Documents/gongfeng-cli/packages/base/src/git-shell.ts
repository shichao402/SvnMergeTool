import Debug from 'debug';
import { replaceBeaconSymbol } from './datahub';
import * as gitUrlParse from 'git-url-parse';
import * as _ from 'lodash';

const debug = Debug('gongfeng:git-shell');

const remoteReg = /(.+)\s+(.+)\s+\((push|fetch)\)/;

export interface Remote {
  name: string;
  resolved?: string;
  fetchUrl?: gitUrlParse.GitUrl;
  pushUrl?: gitUrlParse.GitUrl;
}

export interface Commit {
  sha: string;
  title: string;
}

export interface BranchConfig {
  remoteName?: string;
  remoteUrl?: URL;
  mergeRef?: string;
}

export interface Ref {
  hash: string;
  name: string;
}

export interface TrackingRef {
  remoteName: string;
  branchName: string;
}

/**
 * @deprecated
 * 不在使用，使用 自带的 git 客户端命令来实现
 */
export class Git {
  currentBranch(): string {
    const result = this.exec('symbolic-ref --quiet HEAD');
    return this.getBranchShortName(result);
  }

  topLevelDir(): string {
    const result = this.exec('rev-parse --show-toplevel');
    return this.firstLine(result);
  }

  pathFromRepoRoot(): string {
    const result = this.exec('rev-parse --show-prefix');
    return this.firstLine(result);
  }

  lookupCommit(sha: string, format: string): string {
    return this.exec(`-c log.ShowSignature=false show -s --pretty=format:${format} ${sha}`);
  }

  lastCommit() {
    const result = this.lookupCommit('HEAD', '%H,%s');
    const commit = result.split(',');
    const [sha, title] = commit;
    return {
      sha,
      title,
    };
  }

  commitBody(sha: string) {
    return this.lookupCommit(sha, '%b');
  }

  unCommittedChangeCount(): number {
    const result = this.exec('status --porcelain');
    const lines = result.split('\n');
    let count = 0;
    lines.forEach((line) => {
      if (line !== '') {
        count += 1;
      }
    });
    return count;
  }

  commits(sourceBranch: string, targetBranch: string): Commit[] {
    const result = this.exec(
      `-c log.ShowSignature=false log --pretty=format:%H,%s --cherry ${targetBranch}...${sourceBranch}`,
    );
    const lines = this.outputLines(result);
    const commits: Commit[] = [];
    lines?.forEach((line) => {
      const splits = line.split(',');
      if (splits.length !== 2) {
        return;
      }
      const [sha, title] = splits;
      commits.push({
        sha,
        title,
      });
    });
    return commits;
  }

  readBranchConfig(branch: string) {
    const prefix = _.escapeRegExp(`branch.${branch}`);
    const result = this.exec(`config --get-regexp '^${prefix}.(remote|merge)$'`);
    const lines = this.outputLines(result);
    const config: BranchConfig = {};
    lines.forEach((line) => {
      const splits = line.split(' ');
      if (splits.length < 2) {
        return;
      }
      const [name, value] = splits;
      const keys = name.split('.');
      const key = keys[keys.length - 1];
      if (key === 'remote') {
        if (value.indexOf(':') >= 0) {
          try {
            config.remoteUrl = new URL(value);
          } catch (e) {}
        }
        if (!this.isFileSystemPath(value)) {
          config.remoteName = value;
        }
      }
      if (key === 'merge') {
        config.mergeRef = value;
      }
    });
    return config;
  }

  isFileSystemPath(path: string) {
    return path === '.' || path.startsWith('./') || path.startsWith('/');
  }

  showRefs(...refs: string[]) {
    const ref = refs.join(' ');
    const result = this.exec(`show-ref --verify -- ${ref}`, true);
    const lines = this.outputLines(result);
    const parseRefs: Ref[] = [];
    lines.forEach((line) => {
      const splits = line.split(' ');
      if (splits.length < 2) {
        return;
      }
      const [hash, name] = splits;
      parseRefs.push({
        hash,
        name,
      });
    });
    return parseRefs;
  }

  determineTrackingBranch(remotes: Remote[], branch: string) {
    const refsForLookup = ['HEAD'];
    const trackingRefs: TrackingRef[] = [];

    const branchConfig = this.readBranchConfig(branch);
    if (branchConfig.remoteName) {
      const tr: TrackingRef = {
        remoteName: branchConfig.remoteName,
        branchName: branchConfig.mergeRef?.replace(/^refs\/heads\//, '') ?? '',
      };
      trackingRefs.push(tr);
      refsForLookup.push(this.trackingRefToString(tr));
    }

    remotes.forEach((remote) => {
      const tr: TrackingRef = {
        remoteName: remote.name,
        branchName: branch,
      };
      trackingRefs.push(tr);
      refsForLookup.push(this.trackingRefToString(tr));
    });

    const refs = this.showRefs(...refsForLookup);
    if (refs.length > 1) {
      const sliceRefs = refs.slice(1);
      for (let i = 0; i < sliceRefs.length; i++) {
        const ref = sliceRefs[i];
        if (ref.hash !== refs[0].hash) {
          continue;
        }
        for (let j = 0; i < trackingRefs.length; j++) {
          const tr = trackingRefs[j];
          if (this.trackingRefToString(tr) !== ref.name) {
            continue;
          }
          return tr;
        }
      }
    }
    return null;
  }

  trackingRefToString(tr: TrackingRef) {
    return `refs/remotes/${tr.remoteName}/${tr.branchName}`;
  }

  push(remote: string, ref: string) {
    return this.exec(`push --set-upstream ${remote} ${ref}`);
  }

  // 获取用户已经指定的remote 没有就获取 origin
  remoteUrl() {
    if (this.remotes().length) {
      let remote = this.remotes().find((remote) => remote.resolved === 'target');
      if (remote) {
        return remote.fetchUrl?.href;
      }
      remote = this.remotes().find((remote) => remote.name === 'origin');
      if (remote) {
        return remote.fetchUrl?.href;
      }
    }
    return '';
  }

  // 获取当前项目名
  projectInGroup() {
    const remote = this.remoteUrl();
    return replaceBeaconSymbol(remote).match(/.com\/(\S*).git/)[1] || '';
  }

  projectPathFromRemote(name = 'origin') {
    if (this.remotes().length) {
      const remote = this.remotes().find((r) => r.name === name);
      if (remote) {
        return `${remote.fetchUrl?.owner}/${remote.fetchUrl?.name}`;
      }
    }
    return '';
  }

  findRemoteByProjectPath(projectPath: string) {
    return this.remotes()?.find((remote) => {
      const remoteProjectPath = `${remote.fetchUrl?.owner}/${remote.fetchUrl?.name}`;
      return remoteProjectPath === projectPath;
    });
  }

  listRemotesForPath(path: string): string[] {
    const remoteStrings = this.exec(`-C ${path} remote -v`);
    return this.outputLines(remoteStrings);
  }

  listRemotes(): string[] {
    const remoteStrings = this.exec('remote -v');
    return this.outputLines(remoteStrings);
  }

  remotes(): Remote[] {
    const remoteList = this.listRemotes();
    return this.getRemotes('.', remoteList);
  }

  exec(cmd: string, ignoreError = false): string {
    try {
      return this.execShell(`git ${cmd}`);
    } catch (error: any) {
      if (error.code === 'ENOENT') {
        console.log('Git must be installed to use the GongFeng CLI.  See instructions here: https://git-scm.com');
        throw error;
      }
      debug(`exec stdout: ${error.stdout}`);
      debug(`exec stderr: ${error.stderr}`);
      if (ignoreError) {
        return error.stdout;
      }
      if (error.stderr) {
        throw error;
      }
      return '';
    }
  }

  execShell(cmd: string): string {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { execSync: exec } = require('child_process');
    debug(`exec: ${cmd}`);
    try {
      return exec(`${cmd}`, {
        encoding: 'utf8',
        stdio: [null, 'pipe', null],
      });
    } catch (error: any) {
      throw error;
    }
  }

  outputLines(output: string) {
    const lines = output.replace(/^\n/, '');
    if (!lines) {
      return [];
    }
    return lines.split('\n');
  }

  firstLine(output: string): string {
    return output.split('\n')[0];
  }

  getBranchShortName(output: string) {
    const branch = this.firstLine(output);
    return branch.replace(/^(refs\/heads\/)/, '');
  }

  isLocalBranchExists(branch: string) {
    const result = this.exec(`branch --list ${branch}`);
    return !!result;
  }

  isRemoteBranchExists(remote: string, branch: string) {
    const result = this.exec(`ls-remote --heads ${remote} ${branch}`);
    return !!result;
  }

  getRemotes(path: string, remoteList: string[]) {
    const remotes = this.parseRemotes(remoteList);
    const output = this.exec(`-C ${path} config --get-regexp '^remote\\..*\\.gf-resolved$'`);
    if (!output) {
      return remotes;
    }
    const lines = this.outputLines(output);
    if (!lines?.length) {
      return remotes;
    }
    lines.forEach((line) => {
      const parts = line.split(' ');
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
    return remotes;
  }

  parseRemotes(gitRemotes: string[]): Remote[] {
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

  addRemote(name: string, url: string) {
    this.exec(`remote add -f ${name} ${url}`);
    try {
      const urlParsed = gitUrlParse(url);
      return {
        name,
        fetchUrl: urlParsed,
        pushUrl: urlParsed,
      };
    } catch (e) {}
    return {
      name,
    };
  }

  updateRemoteUrl(name: string, url: string) {
    this.exec(`remote set-url ${name} ${url}`);
  }

  setRemoteResolution(name: string, resolution: string) {
    this.exec(`config --add remote.${name}.gf-resolved ${resolution}`);
  }
}
