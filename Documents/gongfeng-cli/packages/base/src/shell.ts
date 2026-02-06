import Debug from 'debug';
import * as fs from 'fs-extra';
import * as os from 'os';
import * as Path from 'path';
import * as iconv from 'iconv-lite';
import * as chardet from 'chardet';

const debug = Debug('gongfeng:shell');

/**
 * 执行命令行指令
 * @param cmd 命令行指令
 * @param encoding 命令行结果解码编码
 */
export function exec(cmd: string, encoding?: string): string {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { execSync: exec } = require('child_process');
  debug(`exec: ${cmd}`);
  try {
    const buffer = exec(`${cmd}`, {
      stdio: [null, 'pipe', null],
      env: {
        ...process.env,
        LC_ALL: 'en_US.UTF-8',
      },
      maxBuffer: 10 * 1024 * 1024,
    });

    let finalEncoding = encoding;
    if (!finalEncoding) {
      // 未指定编码，默认检测编码
      try {
        finalEncoding = chardet.detect(buffer) || '';
        debug(`auto detect encoding: ${finalEncoding}`);
      } catch (e: any) {
        debug(`auto detect encoding failed: ${e.message}`);
      }
      if (!finalEncoding) {
        // 若未检测出编码则使用 utf8 编码
        finalEncoding = 'utf8';
      }
    }

    return iconv.decode(Buffer.from(buffer), finalEncoding);
  } catch (error: any) {
    throw error;
  }
}

export function isSvnPath(path: string, encoding?: string) {
  const isSvnDirExists = fs.existsSync(`${path}/.svn`) && fs.lstatSync(`${path}/.svn`).isDirectory();
  const isSvnDir2Exists = fs.existsSync(`${path}/_svn`) && fs.lstatSync(`${path}/_svn`).isDirectory();
  if (isSvnDirExists || isSvnDir2Exists) {
    debug('guess vcs svn');
    return true;
  }

  try {
    exec(`svn info ${path}`, encoding);
    return true;
  } catch (error: any) {
    return false;
  }
}

export function getSvnBaseUrl(path: string, encoding?: string) {
  try {
    const data = exec(`svn info ${path}`, encoding);
    const lines = outputLines(data);
    let url = '';
    lines.forEach((line) => {
      const words = line.split(' ');
      if (words.length === 2 && words[0] === 'URL:') {
        url = words[1];
      }
    });
    // 中文会乱码，需先解码
    return decodeURI(url);
  } catch (error: any) {
    return '';
  }
}

function outputLines(output: string) {
  const lines = output.replace(/^\n/, '');
  if (!lines) {
    return [];
  }
  return lines.split(/\r?\n/);
}

export function getSvnDiff(path: string, encoding?: string, revision?: string) {
  try {
    let externalDiff = false;
    const home = os.homedir();
    const svnConfigFile = Path.join(home, '.subversion/config');
    if (fs.existsSync(svnConfigFile) && fs.lstatSync(svnConfigFile).isFile()) {
      const file = fs.readFileSync(svnConfigFile).toString();
      const lines = outputLines(file);
      lines.forEach((line) => {
        if (line.trim().startsWith('diff-cmd')) {
          externalDiff = true;
        }
      });
    }
    let command = 'svn diff ';
    if (externalDiff) {
      const isWindows = process.platform === 'win32';
      if (!isWindows && fs.existsSync('/usr/bin/diff')) {
        debug(
          'Warning! Your svn diff was replaced by another external diff tool, that may case an error when patch files!',
        );
        command = 'svn diff --diff-cmd=/usr/bin/diff ';
      }
    }
    if (revision) {
      command += ` -r ${revision} `;
    }
    command += path;
    const data = exec(command, encoding);
    debug(data);
    const lines = outputLines(data);
    let count = 0;
    lines.forEach((line) => {
      if (line.startsWith('Index:') || line.startsWith('Property changes on:')) {
        count += 1;
      }
    });
    if (count === 0) {
      return [];
    }
    return lines;
  } catch (error: any) {
    throw error;
  }
}

export function getFilenamesFromDiff(diffs: string[]) {
  const filenames: string[] = [];
  diffs.forEach((diff) => {
    if (diff.startsWith('Index:') || diff.startsWith('Property changes on:')) {
      const index = diff.indexOf(':');
      const name = diff.slice(index + 1);
      const filename = name.trim().replace('\\', '/');
      if (!filenames.includes(filename)) {
        filenames.push(filename);
      }
    }
  });
  return filenames;
}

export function getSvnDiffStat(path: string, encoding?: string) {
  try {
    const data = exec(`svn st ${path}`, encoding);
    debug(data);
    return outputLines(data);
  } catch (error: any) {
    return [];
  }
}

export function getFileSvnStatus(filePath: string, encoding?: string): string[] {
  try {
    const data = exec(`svn status -q --ignore-externals ${filePath}`, encoding);
    return outputLines(data);
  } catch (error: any) {
    debug(`get svn status -q --ignore-externals ${filePath} error`);
    return [];
  }
}

export function getSvnInfo(filePath: string, encoding?: string) {
  try {
    const data = exec(`svn info ${filePath}`, encoding);
    return outputLines(data);
  } catch (error: any) {
    debug(`get svn info ${filePath} error`);
    return [];
  }
}

export function getSvnRevisionRange(startTime: string, endTime: string): [string, string] {
  try {
    // 获取SVN工作副本的根目录
    const svnInfoCommand = 'svn info --show-item wc-root';
    const svnRootPath = exec(svnInfoCommand).trim();
    // 格式化时间参数，支持YYYY-MM-DD和YYYY-MM-DDTHH:MM:SS格式
    const formatTime = (timeStr: string) => {
      if (timeStr.includes('T')) {
        // 已经是YYYY-MM-DDTHH:MM:SS格式，直接返回
        return timeStr;
      }
      // YYYY-MM-DD格式，添加默认时间
      return `${timeStr}T00:00:00`;
    };
    const formattedStartTime = formatTime(startTime);

    // 处理endTime为空的情况
    let revisionRange: string;
    if (!endTime || endTime.trim() === '') {
      // 如果endTime为空，获取从起始时间到最新版本的所有revision
      revisionRange = `{"${formattedStartTime}"}:HEAD`;
    } else {
      // 如果endTime不为空，使用指定的时间范围
      const formattedEndTime = formatTime(endTime);
      revisionRange = `{"${formattedStartTime}"}:{"${formattedEndTime}"}`;
    }

    debug(`revision range: ${revisionRange}`);

    // 使用SVN工作副本根目录作为目标路径
    const svnLogCommand = `svn log "${svnRootPath}" -r ${revisionRange} --quiet --incremental`;
    debug(`svn log command: ${svnLogCommand}`);
    const svnLogOutput = exec(svnLogCommand);

    // 解析输出，提取revision号
    const lines = svnLogOutput
      .trim()
      .split('\n')
      .filter((line) => line.trim());
    const revisions = lines.filter((line) => line.startsWith('r')).map((line) => line.split(' ')[0].substring(1));
    if (revisions.length === 0) {
      debug('No revisions found in the specified date range');
      return ['', ''];
    }
    debug(`revisions: ${revisions}`);

    // 返回数组：[起始revision, 终止revision]
    return [revisions[revisions.length - 1], revisions[0]];
  } catch (error) {
    debug(`Error getting SVN revision range: ${error}`);
    return ['', ''];
  }
}

export function getSvnRelativeUrl(path: string = '.', encoding?: string): string {
  try {
    const data = exec(`svn info --show-item relative-url ${path}`, encoding);
    const relativeUrl = data.trim();
    // 去掉开头的 ^ 符号
    return relativeUrl.startsWith('^') ? relativeUrl.slice(1) : relativeUrl;
  } catch (error: any) {
    debug(`get svn relative-url ${path} error: ${error.message}`);
    return '';
  }
}
