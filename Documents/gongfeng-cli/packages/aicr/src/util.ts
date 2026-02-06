import { AIComment, AIReviewFile, AIReviewResult, DiffStatusFile } from './type';
import { color } from '@tencent/gongfeng-cli-base';

const ADDED_FILE = 'A';
const MODIFIED_FILE = 'M';
const DELETED_FILE = 'D';

export function filterFiles(diffStatusFiles?: DiffStatusFile[], files?: string[], skips?: string[]) {
  if (!diffStatusFiles?.length) {
    return [];
  }
  files?.forEach((file) => (file = file.replace(/\\/g, '/')));
  skips?.forEach((skip) => (skip = skip.replace(/\\/g, '/')));
  if (files?.length) {
    const trimFiles = files.map((file) => file.trim());
    diffStatusFiles = diffStatusFiles.filter((file) => trimFiles.includes(file.filePath));
  }
  if (skips?.length) {
    const trimSkips = skips.map((skip) => skip.trim());
    diffStatusFiles = diffStatusFiles.filter((file) => !trimSkips.includes(file.filePath));
  }
  return diffStatusFiles;
}

export function isDeleteOrBinaryFile(diff: string) {
  const lines = diff.split('\n');
  for (const line of lines) {
    if (line.startsWith('deleted file mode') || line.startsWith('Binary files')) {
      return true;
    }
  }
  return false;
}

export function hasDiffContent(diff: string) {
  const lines = diff.split('\n');
  for (const line of lines) {
    if (line.startsWith('@@')) {
      return true;
    }
  }
  return false;
}

export function getDiffStatusFiles(filePaths: string[]) {
  if (!filePaths?.length) {
    return [];
  }
  const diffStatusFiles: DiffStatusFile[] = [];
  filePaths.forEach((path: string) => {
    const status = path.substring(0, 1);
    const filePath = path.substring(1)?.trim();
    const added = status === ADDED_FILE;
    const modified = status === MODIFIED_FILE;
    const deleted = status === DELETED_FILE;
    diffStatusFiles.push({
      added,
      modified,
      deleted,
      filePath,
    });
    return filePaths;
  });
  return diffStatusFiles;
}

export function consoleAIComments(result: AIReviewResult, showAll = false) {
  if (result?.comments?.length) {
    const comments = result.comments;
    const diffs = result.diffs;
    if (showAll) {
      comments.forEach((comment) => {
        showComment(comment, diffs);
      });
    } else {
      const comment = comments[0];
      showComment(comment, diffs);
    }
  }
}

function showComment(comment: AIComment, diffs: AIReviewFile[]) {
  console.log('');
  console.log(`${color.bold(__('file'))}:${color.bold(comment.filePath)}`);
  const diffFile = diffs.find((diff) => diff.filePath === comment.filePath);
  if (diffFile) {
    const newContent = diffFile.newContent;
    const lines = newContent.split('\n');
    const startLine = comment.result.startLine;
    const endLine = comment.result.endLine;

    if (startLine < lines.length && startLine >= 0 && endLine < lines.length && endLine >= 0) {
      for (let i = startLine; i <= endLine; i++) {
        console.log(`${i}: ${lines[i - 1]}`);
      }
    }
    console.log(`${comment.result.content}`);
  }
}

export function printDryRunSummaryBox(title: string, files: string[]): void {
  const newTitle = title || '未命名';
  const border = '='.repeat(80);
  console.log(__('dryRunPrepare'));
  console.log(border);
  console.log(__('dryRunTitle', { title: newTitle }));
  console.log(__('dryRunContainFile', { count: String(files?.length || 0) }));
  if (!files?.length) {
    console.log(border);
    return;
  }
  files.forEach((file) => {
    console.log(`     - ${file}`);
  });
  console.log(border);
}

export function formatTimeToISO(time: Date | string | undefined): string | undefined {
  if (!time) return undefined;
  // 处理字符串格式的时间，确保时间部分为00:00:00
  const timeStr = typeof time === 'string' ? time : time.toISOString();
  // 如果只有日期部分，添加T00:00:00
  if (/^\d{4}-\d{2}-\d{2}$/.test(timeStr)) {
    return `${timeStr}T00:00:00+0800`;
  }
  // 如果包含时间部分，提取日期和时间
  const match = timeStr.match(/^(\d{4}-\d{2}-\d{2})[T\s](\d{2}:\d{2}:\d{2})/);
  if (match) {
    return `${match[1]}T${match[2]}+0800`;
  }
  // 处理其他格式
  const date = new Date(time);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  const seconds = String(date.getSeconds()).padStart(2, '0');
  return `${year}-${month}-${day}T${hours}:${minutes}:${seconds}+0800`;
}

export function getCommentsFiles(comments: AIComment[]) {
  if (!comments?.length) {
    return [];
  }
  const files: string[] = [];
  comments.forEach((comment) => {
    if (!files.includes(comment.filePath)) {
      files.push(comment.filePath);
    }
  });
  return files;
}
