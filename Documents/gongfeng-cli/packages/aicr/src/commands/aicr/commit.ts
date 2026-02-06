import ApiService from '../../api-service';
import BaseCommand from '../../base';
import { color, vars, git, getCurrentRemote, shell } from '@tencent/gongfeng-cli-base';
import Debug from 'debug';
import * as ora from 'ora';
import { Args, Flags } from '@oclif/core';
import { PatchFile } from '../../type';
import {
  consoleAIComments,
  filterFiles,
  getCommentsFiles,
  getDiffStatusFiles,
  hasDiffContent,
  isDeleteOrBinaryFile,
  printDryRunSummaryBox,
} from '../../util';

const debug = Debug('gongfeng-aicr:diff');
const MAX_UPLOAD_FILE_SIZE = 30;

/**
 * aicr commit 评审
 */
export default class Commit extends BaseCommand {
  static strict = false;
  static summary = 'aicr commit 评审';
  static usage = 'aicr commit <commitSha> [-- flags...]';
  static examples = [
    'gf aicr commit c325e4b9',
    'gf aicr commit c325e4b9 -f src/test.js -f src/add.js',
    'gf aicr commit c325e4b9 -s src/test.js -s src/add.js',
  ];

  static args = {
    sha1: Args.string({
      required: false,
      description: '提交ID',
    }),
  };

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
    // 新增参数
    author: Flags.string({
      char: 'A',
      description: '按作者过滤',
    }),
    path: Flags.string({
      char: 'p',
      description: '按路径过滤,只将指定路径下的文件包括在评审内容中',
    }),
    timeback: Flags.string({
      char: 'T',
      description: '按时间过滤,只将从现在开始对指定时间范围内的提交包括在评审内容中,目前只支持天和周,如1d,1w',
    }),
    begintime: Flags.string({
      char: 'B',
      description: '直接给定评审的起始时间,格式为YYYY-MM-DDTHH:MM:SS',
    }),
    endtime: Flags.string({
      char: 'E',
      description: '直接给定评审的结束时间,格式为YYYY-MM-DDTHH:MM:SS',
    }),
    fromversion: Flags.string({
      char: 'F',
      description: '从指定的版本号开始检查',
    }),
    stopversion: Flags.string({
      char: 'S',
      description: '检查到指定的版本号结束',
    }),
    dryrun: Flags.boolean({
      char: 'd',
      default: false,
      description: '演习模式，工蜂copilot告知审查的范围，但是不会开始执行任务',
    }),
    ref: Flags.string({
      char: 'r',
      description: '指定git分支或者tag',
    }),
    cc: Flags.string({
      char: 'C',
      description: '抄送人, 使用英文逗号分隔,支持id或者英文名',
    }),
  };

  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api, this.copilotApi);
    const { args, flags } = await this.parse(Commit);
    const currentPath = process.cwd();

    const projectType = await this.detectProjectType(currentPath);
    if (projectType === 'svn') {
      // SVN项目处理逻辑
      await this.handleSvnCommit(currentPath, args, flags);
    } else if (projectType === 'git') {
      // Git项目处理逻辑
      await this.handleGitCommit(currentPath, args, flags);
    } else {
      console.log(color.error(__('projectTypeError')));
      this.exit(0);
    }
  }

  async getFileContent(filePath: string, root: string, commitSha: string) {
    const fileContent = await git.git(['show', `${commitSha}:${filePath}`], root, 'getCommitFileContent');
    debug(`git show ${commitSha}:${filePath}`);
    if (fileContent.exitCode === 0 && fileContent.stdout) {
      debug(`git show ${commitSha}:${filePath}:\n ${fileContent.stdout}`);
      return fileContent.stdout;
    }
    return '';
  }

  async getPrevFileContent(filePath: string, root: string, commitSha: string) {
    const fileContent = await git.git(['show', `${commitSha}^:${filePath}`], root, 'getPrevCommitFileContent');
    debug(`git show ${commitSha}^:${filePath}`);
    if (fileContent.exitCode === 0 && fileContent.stdout) {
      debug(`git show ${commitSha}^:${filePath}:\n ${fileContent.stdout}`);
      return fileContent.stdout;
    }
    return '';
  }

  async getFileDiff(root: string, filePath: string, commitSha: string) {
    const fileDiff = await git.git(['diff', `${commitSha}^!`, '--', filePath], root, 'getCommitFileDiff');
    debug(`git diff ${commitSha}^! -- ${filePath}`);
    if (fileDiff.exitCode === 0 && fileDiff.stdout) {
      debug(`git diff ${commitSha}^! ${filePath}: \n${fileDiff.stdout}`);
      return fileDiff.stdout;
    }
    return '';
  }

  async getFilePaths(root: string, commitSha: string) {
    const fileResult = await git.git(
      ['diff-tree', '--no-commit-id', '--name-status', '-r', commitSha],
      root,
      'getCommitDiffFilPaths',
    );
    if (fileResult.exitCode !== 0) {
      console.log(color.error(__('getCommitDiffFileFailed')));
      debug(fileResult.stderr);
      this.exit(0);
      return [];
    }
    const filePaths = fileResult.stdout.split('\n').filter((path: string) => path.trim() !== '');
    filePaths.forEach((path: string) => (path = path.replace(/\\/g, '/')));
    return getDiffStatusFiles(filePaths);
  }

  /**
   * 判断当前目录是git项目还是svn项目
   * @param currentPath 当前工作目录
   * @returns 'git' | 'svn' | null
   */
  async detectProjectType(currentPath: string): Promise<'git' | 'svn' | null> {
    debug(`检测项目类型: ${currentPath}`);
    // 检查是否为git项目
    try {
      const gitCheck = await git.git(['rev-parse', '--git-dir'], currentPath, 'checkGit');
      if (gitCheck.exitCode === 0) {
        debug(`检测到git项目: ${currentPath}`);
        return 'git';
      }
    } catch (e) {
      debug(`git检测错误: ${e}`);
    }
    // 检查是否为svn项目
    try {
      if (shell.isSvnPath(currentPath)) {
        debug(`检测到svn项目: ${currentPath}`);
        return 'svn';
      }
    } catch (e) {
      debug(`svn检测错误: ${e}`);
    }

    debug(`未检测到git或svn项目: ${currentPath}`);
    return null;
  }

  // 扩展对于svn commit aicr支持
  async handleSvnCommit(currentPath: string, args: any, flags: any) {
    const svnUrlResult = shell.exec('svn info --show-item repos-root-url');
    const comIndex = svnUrlResult.indexOf('com/');
    const svnPath = (comIndex >= 0 ? svnUrlResult.substring(comIndex + 4) : svnUrlResult).trim();
    const fetchProjectDetailSpinner = ora().start(__('fetchProjectDetail'));
    const targetProject = await this.apiService.getProjectDetail(svnPath);

    if (!targetProject) {
      fetchProjectDetailSpinner.stop();
      console.log(color.error(__('projectNotFound')));
      this.exit();
      return;
    }

    fetchProjectDetailSpinner.stop();

    const options: any = {};
    Object.assign(options, flags);
    if (args.sha1) {
      // 单点commit
      options.stopversion = args.sha1;
      // 如果没有指定路径，则默认为当前目录
      if (!flags.path) {
        options.path = shell.getSvnRelativeUrl();
      }
      await this.createReview(flags, targetProject.id, targetProject.fullPath, [], options);
    } else {
      // 范围commit
      if ((flags.endtime && !flags.begintime) || (flags.stopversion && !flags.fromversion)) {
        // 范围评审必须指定开始时间/版本
        console.log(color.error(__('reviewRangeError')));
        this.exit(0);
      }
      // 处理仅按时间范围过滤的情况
      if (!flags.fromversion) {
        if (flags.begintime || flags.timeback) {
          if (flags.begintime) {
            const revisionRange = shell.getSvnRevisionRange(flags.begintime, flags.endtime);
            options.fromversion = revisionRange[1];
            options.stopversion = revisionRange[0];
          } else {
            // 根据timeback计算出时间
            const now = new Date();
            // 获取UTC+8时区的当前时间
            const offset = 8 * 60 * 60 * 1000;
            const utc8Time = new Date(now.getTime() + offset);
            const endtime = utc8Time.toISOString().slice(0, 19);

            let begintime: string;
            const timeback = flags.timeback.toLowerCase();

            if (timeback.endsWith('d')) {
              // 天为单位
              const days = parseInt(timeback.slice(0, -1));
              const startDate = new Date(utc8Time.getTime() - days * 24 * 60 * 60 * 1000);
              begintime = startDate.toISOString().slice(0, 19);
            } else if (timeback.endsWith('w')) {
              // 周为单位
              const weeks = parseInt(timeback.slice(0, -1));
              const startDate = new Date(utc8Time.getTime() - weeks * 7 * 24 * 60 * 60 * 1000);
              begintime = startDate.toISOString().slice(0, 19);
            } else {
              console.log(color.error(__('timeBackFormatError')));
              this.exit(0);
              return;
            }
            const revisionRange = shell.getSvnRevisionRange(begintime, endtime);
            options.fromversion = revisionRange[1];
            options.stopversion = revisionRange[0];
            options.begintime = begintime;
            options.endtime = endtime;
          }
        }
      }
      // 如果没有指定路径，则默认为当前目录
      if (!flags.path) {
        options.path = shell.getSvnRelativeUrl();
      }
      await this.createReview(flags, targetProject.id, targetProject.fullPath, [], options);
    }
  }

  // 封装对于git commit aicr的支持
  async handleGitCommit(currentPath: string, args: any, flags: any) {
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
      debug(`target remote: ${targetRemote.name}`);
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
    // 如果是单点，需要保持原有逻辑，在cli计算diff
    if (args.sha1) {
      const diffStatusFiles = await this.getFilePaths(root, args.sha1);
      const filteredDiffFiles = filterFiles(diffStatusFiles, flags.files, flags.skips);
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
        const fileDiff = await this.getFileDiff(root, diffFile.filePath, args.sha1);
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
        const content = await this.getFileContent(diffFile.filePath, root, args.sha1);
        if (!content) {
          debug(`${root}/${diffFile.filePath} file content is empty`);
          continue;
        }
        let originalFileContent = '';
        if (diffFile.modified) {
          originalFileContent = await this.getPrevFileContent(diffFile.filePath, root, args.sha1);
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
      const options: any = {};
      Object.assign(options, flags);
      await this.createReview(flags, targetProject.id, targetProject.fullPath, patchFiles, options);
    } else {
      if ((flags.endtime && !flags.begintime) || (flags.stopversion && !flags.fromversion)) {
        // 范围评审必须指定开始时间/版本
        console.log(color.error(__('reviewRangeError')));
        this.exit(0);
      }
      const options: any = {};
      Object.assign(options, flags);
      await this.createReview(flags, targetProject.id, targetProject.fullPath, [], options);
    }
  }

  private async createReview(flags: any, projectId: number, fullPath: string, patchFiles: PatchFile[], options?: any) {
    if (options.files) {
      options.selected = options.files;
      delete options.files;
    }
    if (options.skips) {
      options.exclude = options.skips;
      delete options.skips;
    }
    debug(`createReview options: ${JSON.stringify(options)}`);
    if (flags.background) {
      this.apiService.createAIReview(projectId, flags.title || '', patchFiles, options);
      console.log(__('createAIReviewSucceed'));
      this.exit(0);
    } else {
      const createAIReviewSpinner = ora().start(__('createAIReviewing'));
      const result = await this.apiService.createAIReview(projectId, flags.title || '', patchFiles, options);
      createAIReviewSpinner.stop();
      if (result) {
        // 判断dryrun模式
        if (flags.dryrun) {
          const reviewedFilePaths = result.diffs.map((diffFile) => diffFile.filePath);
          printDryRunSummaryBox(flags.title, reviewedFilePaths);
          this.exit(0);
        }
        const commentCount = result.comments?.length || 0;
        const diffCount = result.diffs?.length || 0;
        if (!diffCount) {
          console.log(color.error(__('noDiffFiles')));
        } else if (!commentCount) {
          console.log(__('noComments'));
        } else {
          const diffs = getCommentsFiles(result.comments);
          const fileCount = diffs.length;
          const firstFileName = diffs[0];
          const url = `https://${vars.host()}/ide/${fullPath}/-/pre_reviews/${result.requestId}`;
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
          consoleAIComments(result, flags.verbose);
        }
      } else {
        console.log(color.error(__('createAIReviewFailed')));
      }
    }
  }
}
