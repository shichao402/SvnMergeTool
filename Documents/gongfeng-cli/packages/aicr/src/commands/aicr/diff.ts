import ApiService from '../../api-service';
import BaseCommand from '../../base';
import { color, vars, git, getCurrentRemote } from '@tencent/gongfeng-cli-base';
import Debug from 'debug';
import * as ora from 'ora';
import { Flags } from '@oclif/core';
import { DiffStatusFile, PatchFile } from '../../type';
import * as fs from 'fs-extra';
import {
  consoleAIComments,
  filterFiles,
  getCommentsFiles,
  getDiffStatusFiles,
  hasDiffContent,
  isDeleteOrBinaryFile,
} from '../../util';

const debug = Debug('gongfeng-aicr:diff');
const MAX_UPLOAD_FILE_SIZE = 30;

/**
 * aicr diff 评审
 */
export default class Diff extends BaseCommand {
  static strict = false;
  static summary = 'aicr diff 评审';
  static usage = 'aicr diff [-- flags...]';
  static examples = [
    'gf aicr diff',
    'gf aicr diff -f src/test.js -f src/add.js',
    'gf aicr diff -s src/test.js -s src/add.js',
  ];

  static flags = {
    title: Flags.string({
      char: 't',
      description: 'aicr 评审标题',
    }),
    files: Flags.string({
      char: 'f',
      description: '指定评审文件(文件路径从 git 项目根目录开始)',
      multiple: true,
    }),
    skips: Flags.string({
      char: 's',
      description: '指定忽略评审文件(文件路径从 git 项目根目录开始)',
      multiple: true,
    }),
    encoding: Flags.string({
      char: 'e',
      default: 'utf-8',
      description: '指定变更编码, 如中文：GB18030',
    }),
    verbose: Flags.boolean({
      char: 'v',
      default: false,
      description: '输出全部 AI 评审结果',
    }),
    background: Flags.boolean({
      char: 'b',
      default: false,
      description: '异步执行创建aicr，不等待结果返回',
    }),
  };

  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api, this.copilotApi);
    const { flags } = await this.parse(Diff);
    const { title, files, skips, encoding, verbose, background } = flags;
    const currentPath = process.cwd();
    const rootGitPath = await git.git(['rev-parse', '--show-toplevel'], currentPath, 'getRootPath');
    if (rootGitPath.exitCode !== 0) {
      console.log(color.error(__('getRootPathError')));
      this.exit(0);
      return;
    }
    const root = rootGitPath.stdout.trim();
    debug(`root path: ${root}`);

    let targetProjectPath: string | null = '';
    let targetRemote = null;
    if (flags.repo) {
      targetProjectPath = flags.repo.trim();
    } else {
      targetRemote = await getCurrentRemote(currentPath);
      if (!targetRemote) {
        console.log(color.error(__('currentRemoteNotFound')));
        this.exit(0);
        return;
      }
      targetProjectPath = await git.projectPathFromRemote(currentPath, targetRemote.name);
    }

    if (!targetProjectPath) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit(0);
      return;
    }

    const fetchProjectDetailSpinner = ora().start(__('fetchProjectDetail'));
    const targetProject = await this.apiService.getProjectDetail(targetProjectPath);
    if (!targetProject) {
      fetchProjectDetailSpinner.stop();
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }
    fetchProjectDetailSpinner.stop();

    const filePaths = await this.getFilePaths(currentPath);
    let filteredDiffFiles = filterFiles(filePaths, files, skips);
    if (!filteredDiffFiles.length) {
      console.log(color.error(__('diffFilesEmpty')));
      this.exit(0);
      return;
    }

    const patchFiles: PatchFile[] = [];
    for (const diffFile of filteredDiffFiles) {
      if (diffFile.deleted) {
        continue;
      }
      const fileDiff = await this.getFileDiff(currentPath, diffFile.filePath, root);
      if (!fileDiff) {
        debug(`${diffFile.filePath} file diff is not found`);
        continue;
      }
      if (isDeleteOrBinaryFile(fileDiff)) {
        debug(`${diffFile.filePath} file is delete or binary`);
        continue;
      }
      if (!hasDiffContent(fileDiff)) {
        debug(`${diffFile.filePath} file diff is empty`);
        continue;
      }
      if (patchFiles.length >= MAX_UPLOAD_FILE_SIZE) {
        console.log(color.warn(__('diffFilesOverSize')));
        break;
      }
      const content = this.getFileContent(diffFile.filePath, root, encoding);
      if (!content) {
        debug(`${root}/${diffFile.filePath} file content is empty`);
        continue;
      }
      let originalFileContent = '';
      if (diffFile.modified) {
        originalFileContent = await this.getOriginalFileContent(diffFile.filePath, root);
      }
      patchFiles.push({
        filePath: diffFile.filePath,
        modifiedFileContent: content,
        diff: fileDiff,
        originalFileContent,
      });
    }

    if (!patchFiles.length) {
      console.log(color.error(__('filterDiffFilesEmpty')));
      this.exit(0);
      return;
    }

    if (background) {
      this.apiService.createAIReview(targetProject.id, title || '', patchFiles);
      console.log(__('createAIReviewSucceed'));
      this.exit(0);
    } else {
      const createAIReviewSpinner = ora().start(__('createAIReviewing'));
      const result = await this.apiService.createAIReview(targetProject.id, title || '', patchFiles);
      createAIReviewSpinner.stop();
      if (result) {
        const commentCount = result.comments?.length || 0;
        if (!commentCount) {
          console.log(__('noComments'));
        } else {
          const diffs = getCommentsFiles(result.comments);
          const fileCount = diffs.length;
          const firstFileName = diffs[0];
          const url = `https://${vars.host()}/ide/${targetProject.fullPath}/-/pre_reviews/${result.requestId}`;
          if (verbose) {
            console.log(
              color.success(
                __('createAIReviewSuccess2', {
                  commentCount: `${commentCount}`,
                  fileCount: `${fileCount}`,
                  filename: firstFileName,
                  url,
                }),
              ),
            );
          } else {
            console.log(
              color.success(
                __('createAIReviewSuccess', {
                  commentCount: `${commentCount}`,
                  fileCount: `${fileCount}`,
                  filename: firstFileName,
                  url,
                }),
              ),
            );
          }
          consoleAIComments(result, verbose);
        }
      } else {
        console.log(color.error(__('createAIReviewFailed')));
      }
    }
  }

  getFileContent(filePath: string, root: string, encoding: string = 'utf-8') {
    if (fs.existsSync(`${root}/${filePath}`)) {
      debug(`${root}/${filePath} file exists`);
      return fs.readFileSync(`${root}/${filePath}`, { encoding: encoding as BufferEncoding });
    }
    debug(`${root}/${filePath} file not exists`);
    return '';
  }

  async getOriginalFileContent(filePath: string, root: string) {
    const result = await git.git(['show', `HEAD:${filePath}`], root, 'getOriginalFileContent');
    if (result.exitCode === 0 && result.stdout) {
      debug(`git show Head:${filePath}: ${result.stdout}`);
      return result.stdout;
    }
    return '';
  }

  async getFileDiff(currentPath: string, filePath: string, root: string) {
    const absolutFilePath = `${root}/${filePath}`;
    let fileDiff = await git.git(['diff', '--cached', '--', absolutFilePath], currentPath, 'getCachedDiff');
    debug(`git diff --cached -- ${absolutFilePath}`);
    if (fileDiff.exitCode === 0 && fileDiff.stdout) {
      debug(`git diff --cached: ${fileDiff.stdout}`);
      return fileDiff.stdout;
    }
    fileDiff = await git.git(['diff', absolutFilePath], currentPath, 'getDiff');
    debug(`git diff ${absolutFilePath}`);
    if (fileDiff.exitCode === 0 && fileDiff.stdout) {
      debug(`git diff ${absolutFilePath}: ${fileDiff.stdout}`);
      return fileDiff.stdout;
    }
    return '';
  }

  async getFilePaths(currentPath: string): Promise<DiffStatusFile[]> {
    const fileResult = await git.git(['diff', '--cached', '--name-status'], currentPath, 'getCachedDiffFilPaths');
    if (fileResult.exitCode !== 0) {
      console.log(color.error(__('getCachedDiffFailed')));
      debug(fileResult.stderr);
      this.exit(0);
      return [];
    }
    let filePaths = fileResult.stdout.split('\n').filter((path: string) => path.trim() !== '');
    if (!filePaths?.length) {
      const fileResult = await git.git(['diff', '--name-status'], currentPath, 'getDiffFilPaths');
      if (fileResult.exitCode !== 0) {
        console.log(color.error(__('getDiffFailed')));
        debug(fileResult.stderr);
        this.exit(0);
        return [];
      }
      filePaths = fileResult.stdout.split('\n').filter((path: string) => path.trim() !== '');
    }
    filePaths.forEach((path: string) => (path = path.replace(/\\/g, '/')));
    return getDiffStatusFiles(filePaths);
  }
}
