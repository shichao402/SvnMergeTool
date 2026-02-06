import * as fs from 'fs';
import { AuthHeader, Placeholder, PlaceholderType, Platform } from './type';
import axios from 'axios';
import * as path from 'path';
import { authToken, loginUser } from '@tencent/gongfeng-cli-base';
import { v4 as uuidv4 } from 'uuid';

export const getPlatform = (): Platform => {
  const { platform } = process;
  switch (platform) {
    case 'win32':
      return Platform.WIN;
    case 'darwin':
      if (process.arch === 'arm64') {
        return Platform.MAC;
      }
      return Platform.MAC_AMD;
    case 'linux':
      return Platform.LINUX;
    default:
      return Platform.LINUX;
  }
};

export function isWindows() {
  if (typeof process !== 'undefined') {
    return /^win/.test(process.platform);
  }
  return false;
}

export async function getAuthHeader(): Promise<AuthHeader> {
  const token = await authToken();
  const username = await loginUser();
  return {
    'OAUTH-TOKEN': token || '',
    'X-Username': username || '',
  };
}

export const download = async (url: string, dest: string, fileName: string) => {
  await fs.promises.mkdir(dest, { recursive: true });
  try {
    const tempFilePath = path.join(dest, `${uuidv4()}.tmp`);
    const targetPath = path.join(dest, fileName);
    const response = await axios.get(url, {
      responseType: 'stream',
      headers: await getAuthHeader(),
    });
    const writer = fs.createWriteStream(tempFilePath);
    await new Promise((resolve, reject) => {
      writer.on('finish', resolve);
      writer.on('error', (writeErr) => {
        reject(new Error(`文件写入失败: ${writeErr.message}`));
      });
      response.data.pipe(writer);
    });
    await fs.promises.rename(tempFilePath, targetPath);
  } catch (error) {
    const errMsg = `下载失败 (${url}): ${error instanceof Error ? error.message : error}`;
    throw new Error(errMsg);
  }
};

/**
 * 是否具有可执行权限
 * @param filePath 文件路径
 * @returns
 */
export const hasExecutablePermission = async (filePath: string): Promise<boolean> => {
  try {
    await fs.promises.access(filePath, fs.constants.X_OK);
    return true;
  } catch (err) {
    return false;
  }
};

/**
 * 添加可执行权限
 */
export const addExecutablePermission = async (path: string): Promise<void> => {
  if (!(await hasExecutablePermission(path))) {
    await fs.promises.chmod(path, 0o755);
  }
};

/**
 * 日期格式化
 * @param date
 * @returns
 */
export function getFormatDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hour = String(date.getHours()).padStart(2, '0');
  const minute = String(date.getMinutes()).padStart(2, '0');

  return `${year}-${month}-${day} ${hour}:${minute}`;
}

/**
 * 获取目录下的所有文件
 */
export function getAllFilesFromDir(dir: string): string[] {
  const files: string[] = [];
  const items = fs.readdirSync(dir);
  items.forEach((item) => {
    const itemPath = path.join(dir, item);
    const stat = fs.statSync(itemPath);
    if (stat.isDirectory()) {
      files.push(...getAllFilesFromDir(itemPath));
    } else {
      files.push(itemPath);
    }
  });
  return files;
}

export function debounce<T extends (...args: any[]) => void>(func: T, delay: number): T {
  let timeoutId: ReturnType<typeof setTimeout>;
  return function (...args: Parameters<T>) {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => {
      // @ts-expect-error
      func.apply(this, args);
    }, delay);
  } as T;
}

export function normalizePath(p: string) {
  const normalized = path.normalize(p);
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

export function formatText(text: string, placeholder?: Record<string, Placeholder>) {
  if (!placeholder) {
    return text;
  }
  const regex = /\[\[(.*?)\]\]/g;
  const matches = Array.from(text.matchAll(regex));
  const textArr = matches.map((m) => m[1]);
  let res = text;
  if (textArr.length) {
    textArr.forEach((item) => {
      const placeholderInfo = placeholder[item];
      switch (placeholderInfo?.type) {
        case PlaceholderType.JUMP_FILE:
          res = text.replace(`[[${item}]]`, '');
          break;
        case PlaceholderType.JUMP_LINK:
          res = text.replace(`[[${item}]]`, `${placeholderInfo.name}(${placeholderInfo.path})`);
          break;
        case PlaceholderType.JUMP_TAB:
          res = text.replace(`[[${item}]]`, '');
          break;
        default:
          break;
      }
    });
  }
  return res;
}
