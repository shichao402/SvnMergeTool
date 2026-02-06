import * as gitUrlParse from 'git-url-parse';

export interface Remote {
  name: string;
  resolved?: string;
  fetchUrl?: gitUrlParse.GitUrl;
  pushUrl?: gitUrlParse.GitUrl;
}

export interface TrackingRef {
  remoteName: string;
  branchName: string;
}
