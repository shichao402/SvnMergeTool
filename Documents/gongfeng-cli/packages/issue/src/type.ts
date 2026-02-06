import { Label, User } from '@tencent/gongfeng-cli-base';

export enum IssueState {
  OPENED = 'opened',
  CLOSED = 'closed',
  REOPENED = 'reopened',
  ALL = 'all', // 用于 tabs
}
export type ApiUserMixin = Pick<User, 'username' | 'id' | 'name' | 'state'>;

export interface IssueFacade extends Issue {
  labels: Label[];
  noteCount: number;
  assignees: User[] | null;
  author: User;
  titleHtml: string;
}

export interface Issue {
  id: number;
  iid: number;
  titleRaw: string;
  state: IssueState;
  resolvedState: string | null;
  priority: number;
  position: number;
  branchName: string | null;
  description: string;
  confidential: boolean;
  pinned: boolean;
  forkedFrom: number;
  createdAt: number;
  updatedAt: number;
  resolvedAt: number | null;
  descriptionUpdatedAt: number;
}
