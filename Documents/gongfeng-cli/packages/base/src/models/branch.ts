import { Commit } from './commit';
import { removeRemotePrefix } from '../common/remove-remote-prefix';
import { CommitIdentity } from './commit-identity';

// NOTE: The values here matter as they are used to sort
// local and remote branches, Local should come before Remote
export enum BranchType {
  Local = 0,
  Remote = 1,
}

/** The number of commits a revision range is ahead/behind. */
export interface IAheadBehind {
  readonly ahead: number;
  readonly behind: number;
}

/** The result of comparing two refs in a repository. */
export interface ICompareResult extends IAheadBehind {
  readonly commits: ReadonlyArray<Commit>;
}

/** Basic data about a branch, and the branch it's tracking. */
export interface ITrackingBranch {
  readonly ref: string;
  readonly sha: string;
  readonly upstreamRef: string;
  readonly upstreamSha: string;
}

/** Basic data about the latest commit on the branch. */
export interface IBranchTip {
  readonly sha: string;
  readonly author: CommitIdentity;
}

/** Basic data about merge and remote info on the branch */
export interface BranchConfig {
  remoteName?: string;
  remoteUrl?: URL;
  mergeRef?: string;
}

/** Default rules for where to create a branch from */
export enum StartPoint {
  CurrentBranch = 'CurrentBranch',
  DefaultBranch = 'DefaultBranch',
  Head = 'Head',
  /** Only valid for forks */
  UpstreamDefaultBranch = 'UpstreamDefaultBranch',
}

/** A branch as loaded from Git. */
export class Branch {
  /**
   * A branch as loaded from Git.
   *
   * @param name The short name of the branch. E.g., `master`.
   * @param upstream The remote-prefixed upstream name. E.g., `origin/master`.
   * @param tip Basic information (sha and author) of the latest commit on the branch.
   * @param type The type of branch, e.g., local or remote.
   * @param ref The canonical ref of the branch
   */
  public constructor(
    public readonly name: string,
    public readonly upstream: string | null,
    public readonly tip: IBranchTip,
    public readonly type: BranchType,
    public readonly ref: string,
  ) {}

  /** The name of the upstream's remote. */
  public get upstreamRemoteName(): string | null {
    const upstream = this.upstream;
    if (!upstream) {
      return null;
    }

    const pieces = upstream.match(/(.*?)\/.*/);
    if (!pieces || pieces.length < 2) {
      return null;
    }

    return pieces[1];
  }

  /** The name of remote for a remote branch. If local, will return null. */
  public get remoteName(): string | null {
    if (this.type === BranchType.Local) {
      return null;
    }

    const pieces = this.ref.match(/^refs\/remotes\/(.*?)\/.*/);
    if (!pieces || pieces.length !== 2) {
      // This shouldn't happen, the remote ref should always be prefixed
      // with refs/remotes
      throw new Error(`Remote branch ref has unexpected format: ${this.ref}`);
    }
    return pieces[1];
  }
  /**
   * The name of the branch's upstream without the remote prefix.
   */
  public get upstreamWithoutRemote(): string | null {
    if (!this.upstream) {
      return null;
    }

    return removeRemotePrefix(this.upstream);
  }

  /**
   * The name of the branch without the remote prefix. If the branch is a local
   * branch, this is the same as its `name`.
   */
  public get nameWithoutRemote(): string {
    if (this.type === BranchType.Local) {
      return this.name;
    }
    const withoutRemote = removeRemotePrefix(this.name);
    return withoutRemote || this.name;
  }
}
