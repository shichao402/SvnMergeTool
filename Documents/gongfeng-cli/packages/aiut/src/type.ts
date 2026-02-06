export enum Platform {
  LINUX = 'linux',
  MAC = 'mac',
  MAC_AMD = 'mac-amd',
  WIN = 'win',
}

export interface AuthHeader {
  'OAUTH-TOKEN': string;
  'X-Username': string;
  [key: string]: string;
}

export interface ProjectInfo {
  is_valid?: boolean;
  lang?: string;
  error?: string;
}

export enum GenType {
  FILE = 'file',
  PROJECT = 'project',
}

export enum GenScene {
  MANUAL_GEN_BY_PROJECT = 'manualGenByProject',
  MANUAL_GEN_BY_FILE = 'manualGenByFile',
}

export enum CaseGenType {
  ALL = 'all',
  SKIP_EXIST = 'skip_exist',
}

export enum ReferenceType {
  CONTEXT = 'context',
  FILE = 'file',
  OFFICIAL = 'official',
}

export enum UnitTestUpdateStatus {
  GENERATING = 'generating',
  WAITING = 'waiting',
  ERROR = 'error',
  FINISH = 'finish',
  CURRENT = 'current',
}

export enum PlaceholderType {
  JUMP_FILE = 'jump_file',
  JUMP_LINK = 'jump_link',
  JUMP_TAB = 'jump_tab',
}

export interface Placeholder {
  type: PlaceholderType;
  name: string;
  path: string;
}
