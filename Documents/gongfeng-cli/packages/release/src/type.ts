import { Label, User, Commit } from '@tencent/gongfeng-cli-base';

export interface TagReleaseFacade {
  labels: Label[];
  ref: RefModel;
  release: ReleaseFacade;
  attachments?: Attachments[];
}

export interface ReleaseFacade extends Release {
  author: User;
}

export interface Release {
  id: number;
  projectId: number;
  authorId: number;
  tag: string;
  title: string;
  type: string;
  attachments: string;
  description: string;
  createdAt: number;
  updatedAt: number;
}

export interface RefModel {
  name: string;
  shortName: string;
  author: User;
  email: string;
  extraMessage: string;
  commit: Commit;
}

export interface Attachments {
  name: string;
  url: string;
  type: string;
  size: number;
  createAt: number;
}
