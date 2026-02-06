export interface PatchFile {
  filePath: string;
  diff: string;
  modifiedFileContent: string;
  originalFileContent?: string;
}

export interface DiffStatusFile {
  filePath: string;
  content?: string;
  added?: boolean;
  modified?: boolean;
  deleted?: boolean;
}

export interface AIReviewResult {
  requestId: string;
  status: number;
  comments: AIComment[];
  diffs: AIReviewFile[];
}

export interface AIReviewFile {
  filePath: string;
  newContent: string;
  diff: string;
  oldContent: string;
}

export interface AIComment {
  result: AIReviewResult;
  function: AIFunction;
  filePath: string;
}

export interface AIReviewResult {
  id: number;
  taskId: number;
  content: string;
  startLine: number;
  endLine: number;
  displayLine: number;
  level: number;
}

export interface AIFunction {
  filePath: string;
  startLine: number;
  endLine: number;
}
