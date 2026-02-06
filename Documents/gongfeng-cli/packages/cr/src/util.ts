import { shell } from '@tencent/gongfeng-cli-base';
import { ProjectVisibilityLevel, SvnReviewableType } from './type';
import { ReviewableType } from '@tencent/gongfeng-cli-base/dist/gong-feng';

export const SEPARATOR = ',';
export const MAX_UPLOAD_SIZE = 5 * 1024 * 1024;
const IGNORE_FILE_SUFFIX = [
  'jar',
  'class',
  'svn',
  'dll',
  'bmp',
  'jpeg',
  'jpg',
  'png',
  'gif',
  'pic',
  'tif',
  'iso',
  'rar',
  'zip',
  'exe',
  'pdf',
  'rm',
  'avi',
  'wav',
  'aif',
  'au',
  'mp3',
  'ram',
  'mpg',
  'mov',
  'swf',
  'xls',
  'xlsx',
  'doc',
  'docx',
  'mid',
  'ppt',
  'pptx',
  'mmap',
  'msi',
  'lib',
  'ilk',
  'obj',
  'aps',
  'def',
  'dep',
  'pdb',
  'tlb',
  'res',
  'manifest',
  'hlp',
  'wps',
  'arj',
  'gz',
  'z',
  'adt',
  'com',
  'a',
  'bin',
  '3ds',
  'drw',
  'dxf',
  'eps',
  'psd',
  'wmf',
  'pcd',
  'pcx',
  'psp',
  'rle',
  'raw',
  'sct',
  'tga',
  'tiff',
  'u3d',
  'xbm',
];

export function filterData(
  path: string,
  diffLines: string[],
  diffFiles: string[],
  keepFiles?: string[],
  skipFiles?: string[],
) {
  if (!diffLines?.length) {
    return [];
  }
  if (!diffFiles?.length) {
    return [];
  }
  let files = filterFiles(path, diffFiles, keepFiles);
  files = filterSkipFiles(path, files, skipFiles);
  if (!files?.length) {
    return [];
  }
  const newDiffLines: string[] = [];
  let keepLine = false;
  let lastLine = '';
  const currFiles: string[] = [];
  let isHeadLineDiff = false;
  diffLines.forEach((line) => {
    if (line.startsWith('Index:')) {
      const index = line.indexOf(':');
      const name = line.slice(index + 1);
      const filepath = name.trim().replace(/\\/g, '/');
      if (files.includes(filepath) && !currFiles.includes(filepath)) {
        if (isBinaryFile(filepath)) {
          keepLine = false;
          newDiffLines.push(...binaryFileDiff(path, filepath));
        } else {
          keepLine = true;
        }
        const filename = removeFileBase(path, filepath);
        currFiles.push(filename);
        line = `Index: ${filename}`;
      } else {
        keepLine = false;
      }
    }
    if (keepLine) {
      // 把 diff 的绝对路径转换成相对路径
      // ==================          ==================
      // --- /users/test/a.txt    => --- a.txt
      // +++ /users/test/a.txt       +++ a.txt
      if (
        line.startsWith('--- ') &&
        lastLine.trim() === '==================================================================='
      ) {
        line = checkCopyFrom(line);
        line = fixRelativePath(path, line);
        isHeadLineDiff = true;
      }
      if (line.startsWith('+++ ') && isHeadLineDiff) {
        line = fixRelativePath(path, line);
        isHeadLineDiff = false;
      }
      newDiffLines.push(line);
    }
    lastLine = line;
  });
  return [newDiffLines, currFiles];
}

export function fixRelativePath(path: string, line: string) {
  const prefix = line.substring(0, 4);
  let suffix = line.substring(4);
  suffix = suffix.replace(/\\/g, '/').replace(path, '');
  if (suffix.startsWith('/')) {
    suffix = suffix.substring(1);
  }
  return `${prefix}${suffix}`;
}

export function filterStData(
  path: string,
  diffLines: string[],
  diffFiles: string[],
  keepFiles?: string[],
  skipFiles?: string[],
) {
  if (!diffLines?.length) {
    return [];
  }
  if (!diffFiles?.length) {
    return [];
  }
  let files = filterFiles(path, diffFiles, keepFiles);
  files = filterSkipFiles(path, files, skipFiles);
  if (!files?.length) {
    return [];
  }
  const newDiffLines: string[] = [];
  const currFiles: string[] = [];
  diffLines.forEach((line) => {
    const prefix = line.substring(0, 8);
    const filepath = line.substring(8).trim().replace(/\\/g, '/');
    if (filepath && files.includes(filepath)) {
      let relativePath = filepath.replace(path, '');
      if (relativePath.startsWith('/')) {
        relativePath = relativePath.substring(1);
      }
      newDiffLines.push(`${prefix}${relativePath}`);
      const filename = removeFileBase(path, filepath);
      currFiles.push(filename);
    }
  });
  return [newDiffLines, currFiles];
}

export function filterFiles(path: string, diffFiles: string[], files?: string[]) {
  if (!files?.length) {
    return diffFiles;
  }
  const keepFiles: string[] = [];
  const keepList: string[] = [];
  files.forEach((file) => {
    let keep = path + '/' + file.trim();
    keep = keep.replace(/\\/g, '/');
    keepList.push(keep);
  });
  diffFiles.forEach((diffFile) => {
    if (isSubFile(keepList, diffFile)) {
      keepFiles.push(diffFile);
    }
  });
  return keepFiles;
}

function isSubFile(keepList: string[], filePath: string) {
  let isSub = false;
  keepList.forEach((keep) => {
    if (keep === filePath || filePath.startsWith(keep)) {
      isSub = true;
    }
  });
  return isSub;
}

export function filterSkipFiles(path: string, diffFiles: string[], skipFiles?: string[]) {
  if (!skipFiles?.length) {
    return diffFiles;
  }
  const files: string[] = [];
  const skips: string[] = [];
  skipFiles.forEach((file) => {
    let skip = path + '/' + file.trim();
    skip = skip.replace(/\\/g, '/');
    skips.push(skip);
  });
  diffFiles.forEach((diffFile) => {
    const isSkip = isSubFile(skips, diffFile);
    if (!isSkip) {
      files.push(diffFile);
    }
  });
  return files;
}

export function isBinaryFile(filename: string) {
  const extension = filename.split('.').pop();
  if (extension) {
    return IGNORE_FILE_SUFFIX.includes(extension.toLowerCase());
  }
  return false;
}

function binaryFileDiff(path: string, filePath: string) {
  const lines = shell.getFileSvnStatus(filePath);
  let isDeletedFile = false;
  let revision = 'none';
  lines?.forEach((line: string) => {
    if (line.startsWith('D')) {
      const path = line.substring(4).trim().replace(/\\/g, '/');
      if (path === filePath) {
        isDeletedFile = true;
      }
    }
  });
  if (isDeletedFile) {
    const lines = shell.getSvnInfo(filePath);
    lines?.forEach((line: string) => {
      const words = line.split(': ');
      if (words.length === 2) {
        if (words[0] === 'Last Changed Rev') {
          revision = words[1];
        }
      }
    });
  }
  const binaryLines = [
    `Index: ${removeFileBase(path, filePath)}`,
    '===================================================================',
    `--- ${removeFileBase(path, filePath)}\t(revision ${revision})`,
    `+++ ${removeFileBase(path, filePath)}\t(working copy)`,
  ];
  if (isDeletedFile) {
    binaryLines.push('@@ -1,1 +0,0 @@');
    binaryLines.push('-');
  } else {
    binaryLines.push('@@ -0,0 +1,0 @@');
    binaryLines.push('+');
  }
  return binaryLines;
}

function removeFileBase(path: string, filePath: string) {
  const filename = filePath.substring(path.length + 1);
  if (filename?.length) {
    return filename;
  } else {
    const lastSlash = filePath.lastIndexOf('/');
    return filePath.substring(lastSlash + 1);
  }
}

// the param 'leftLine' should like: --- bc1/nice2.txt  (revision 458)
function checkCopyFrom(line: string) {
  const filePath = line.substring(4, line.indexOf('(')).trim();
  const lines = shell.getSvnInfo(filePath);
  if (!lines.length) {
    return line;
  }
  let retLine = '--- ';
  let isCopy = false;
  let curRev = '-1';
  lines.forEach((line: string) => {
    const words = line.split(': ');
    if (words.length === 2) {
      if (words[0] === 'Copied From URL') {
        isCopy = true;
        retLine += formatSvnUrl(words[1]);
      } else if (words[0] === 'Copied From Rev') {
        retLine += `\t(revision ${words[1]})`;
      } else if (words[0] === 'Revision') {
        curRev = words[1];
      }
    }
  });
  if (isCopy) {
    return retLine;
  } else if (parseInt(curRev, 10) > 0) {
    return `${retLine}${filePath}\t(revision ${curRev})`;
  }
  return line;
}

function formatSvnUrl(url: string) {
  return url.replace(/svn\+ssh:\/\/(\w*?@)?/, 'https://');
}

export function checkCopyFile(path: string, files: string[], filterFiles?: string[]) {
  const curFileNames = files;
  const lines: string[] = [];
  const statusLines = shell.getFileSvnStatus(path);
  statusLines?.forEach((line: string) => {
    if (line.startsWith('A  +')) {
      const filePath = line.substring(4).trim().replace(/\\/g, '/');
      const filename = removeFileBase(path, filePath);
      if (!curFileNames.includes(filename) && (!filterFiles?.length || filterFiles?.includes(filename))) {
        lines.push(`Index: ${filename}`);
        lines.push('===================================================================');
        lines.push(checkCopyFrom(`--- ${filePath}\t(revision -1)`));
        lines.push(`+++ ${filePath}\t(working copy)`);
      }
    }
  });
  return lines;
}

export function getFilesFromDiffSt(diffs: string[]) {
  if (!diffs?.length) {
    return [];
  }
  const files: string[] = [];
  diffs.forEach((line) => {
    const filepath = line.substring(4).trim().replace(/\\/g, '/');
    if (filepath) {
      files.push(filepath);
    }
  });
  return files;
}

export function isPublicProject(visibilityLevel: number) {
  return visibilityLevel === ProjectVisibilityLevel.Public;
}

export function isInternalProject(visibilityLevel: number) {
  return visibilityLevel === ProjectVisibilityLevel.Internal;
}

export function isPrivateProject(visibilityLevel: number) {
  return visibilityLevel === ProjectVisibilityLevel.Private;
}

export function isPublic(visibilityLevel: number) {
  return isPublicProject(visibilityLevel) || isInternalProject(visibilityLevel);
}

export function isCodeInLocal(review?: { reviewableType: SvnReviewableType | ReviewableType }) {
  return review?.reviewableType === SvnReviewableType.SVN_MERGE_REQUEST;
}
