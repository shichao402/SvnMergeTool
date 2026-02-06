import { Flags, Args } from '@oclif/core';
import BaseCommand from '../../base';
import {
  shell,
  color,
  User,
  UserSelectChoice,
  vars,
  getErrorMessage,
  getUrlWithAdTag,
} from '@tencent/gongfeng-cli-base';
import { checkCopyFile, filterData, filterStData, getFilesFromDiffSt, SEPARATOR, MAX_UPLOAD_SIZE } from '../../util';
import ApiService from '../../api-service';
import * as inquirer from 'inquirer';
// @ts-ignore
import * as CheckboxPlus from 'inquirer-checkbox-plus-prompt';
import { TapdTicketForm } from '../../type';
import Debug from 'debug';
import * as ora from 'ora';

const debug = Debug('gongfeng-cr:create');
inquirer.registerPrompt('checkbox-plus', CheckboxPlus);
const DEFAULT_DESC = '(created by GF CLI)';

export default class Create extends BaseCommand {
  static summary = '创建代码评审(目前只支持 svn 代码在本地模式)';
  static description = '可以指定 svn 项目路径或者不指定路径(即命令当前所在路径)创建代码在本地的代码评审';
  static examples = ['gf cr create /users/project/test/trunk', 'gf cr create'];
  static usage = 'cr create [path] [flags]';

  static args = {
    path: Args.string({
      required: false,
      description: 'svn 项目路径',
    }),
  };

  static flags = {
    title: Flags.string({
      char: 't',
      description: '代码评审标题',
      helpGroup: '公共参数',
    }),
    description: Flags.string({
      char: 'd',
      description: '代码请求描述',
      helpGroup: '公共参数',
    }),
    reviewer: Flags.string({
      char: 'r',
      description: '通过用户名指定评审人，使用英文逗号(,)分割',
      helpGroup: '公共参数',
    }),
    quick: Flags.boolean({
      char: 'q',
      description: '快速发起代码评审，所有字段使用默认值',
      helpGroup: '公共参数',
    }),
    tapd: Flags.string({
      description: '关联 TAPD 需求单',
      helpGroup: 'SVN 代码评审参数',
    }),
    cc: Flags.string({
      char: 'c',
      description: '抄送人, 使用英文逗号(,)分割',
      helpGroup: 'SVN 代码评审参数',
    }),
    author: Flags.string({
      char: 'a',
      description: '指定代码评审作者',
      helpGroup: 'SVN 代码评审参数',
    }),
    'only-filename': Flags.boolean({
      description: '只发起文件名评审',
      default: false,
      helpGroup: 'SVN 代码评审参数',
    }),
    files: Flags.string({
      char: 'f',
      description: '指定需评审文件',
      multiple: true,
      helpGroup: 'SVN 代码评审参数',
    }),
    skips: Flags.string({
      char: 's',
      description: '指定需跳过评审的文件',
      multiple: true,
      helpGroup: 'SVN 代码评审参数',
    }),
    encoding: Flags.string({
      char: 'e',
      description: '指定变更编码, 如中文：GB18030',
      helpGroup: 'SVN 代码评审参数',
    }),
  };

  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { args, flags } = await this.parse(Create);
    let { path } = args;
    if (!path) {
      path = process.cwd();
    } else {
      // 支持相对路径
      if (path.startsWith('./')) {
        path = process.cwd() + path.substring(1);
      }
    }
    path = path.replace(/\\/g, '/');
    debug(`path: ${path}`);
    let { title, description } = flags;
    const { reviewer, cc, tapd, quick, files, skips, 'only-filename': onlyFilename, author, encoding } = flags;
    if (shell.isSvnPath(path, encoding)) {
      const svnBase = shell.getSvnBaseUrl(path, encoding);
      debug(`svnBase: ${svnBase}`);
      const fetchSpinner = ora().start(__('fetchProjectDetail'));
      const project = await this.apiService.getSvnProject(svnBase);
      if (!project) {
        fetchSpinner.stop();
        console.log(color.error(__('projectNotFound')));
        return;
      }
      debug(`projectPath: ${project.fullPath}`);
      const projectId = project.id;
      const urls: string[] = [];
      let data = '';
      if (!onlyFilename) {
        try {
          const diffs = shell.getSvnDiff(path, encoding);
          if (!diffs?.length) {
            fetchSpinner.stop();
            console.log(color.warn(__('noDiff')));
            return;
          }
          const diffFiles = shell.getFilenamesFromDiff(diffs);
          debug(`source diffs: ${diffs.join('\r\n')}`);
          debug(`source files: ${diffFiles.join(', ')}`);
          const [lines, currentFiles] = filterData(path, diffs, diffFiles, files, skips);
          if (!lines?.length) {
            fetchSpinner.stop();
            console.log(color.warn(__('noDiff')));
            return;
          }

          const appendLines = checkCopyFile(path, currentFiles, files);
          lines.push(...appendLines);

          data = lines.join('\r\n');
          debug(`filter diffs: ${data}`);
          debug(`filter files: ${currentFiles.join(', ')}`);
          if (data.length > MAX_UPLOAD_SIZE) {
            fetchSpinner.stop();
            console.log(color.error(__('diffTooLarge')));
            return;
          }
          if (data.length === 0) {
            fetchSpinner.stop();
            console.log(color.error(__('diffEmpty')));
            return;
          }

          currentFiles.forEach((file) => {
            urls.push(`${svnBase}/${file}`);
          });
        } catch (error: any) {
          fetchSpinner.stop();
          if (error.code === 'ENOBUFS') {
            console.log(color.error(__('diffTooLargeError')));
          } else {
            console.log(color.error(__('diffError')));
          }
          debug(`get svn diff failed: ${error.message}`);
          this.exit(0);
          return;
        }
      } else {
        const diffs = shell.getSvnDiffStat(path, encoding);
        const diffFiles = getFilesFromDiffSt(diffs);
        const [lines, currentFiles] = filterStData(path, diffs, diffFiles, files, skips);
        if (!lines?.length) {
          fetchSpinner.stop();
          console.log(color.warn(__('noDiff')));
          return;
        }

        data = lines.join('\r\n');
        debug(`filter diffs: ${data}`);
        debug(`filter files: ${currentFiles.join(', ')}`);
        if (data.length > MAX_UPLOAD_SIZE) {
          fetchSpinner.stop();
          console.log(color.error(__('diffTooLarge')));
          return;
        }
        currentFiles.forEach((file) => {
          urls.push(`${svnBase}/${file}`);
        });
      }
      fetchSpinner.stop();
      debug(`owner urls: ${urls.join(', ')}`);
      const reviewerSpinner = ora().start(__('fetchReviewers'));
      const defaultReviewers = await this.getPreConfig(project.id, urls);
      reviewerSpinner.stop();

      let reviewerIds: number[] = [];
      let inputReviewers: User[] = [];
      let tapdTickets: TapdTicketForm[] = [];
      if (tapd) {
        tapdTickets = await this.getTapdTicket(tapd);
      }
      let ccIds = undefined;
      if (cc) {
        ccIds = await this.getCcIds(cc);
      }

      if (quick || (title && description)) {
        if (reviewer) {
          inputReviewers = await this.getReviewers(reviewer);
        }
        await this.quickSvnCr(
          path,
          projectId,
          project.fullPath,
          data,
          onlyFilename,
          svnBase,
          defaultReviewers,
          inputReviewers,
          tapdTickets,
          ccIds,
          author,
          title,
          description,
        );
        return;
      }
      const questions = [];
      if (!title) {
        questions.push({
          type: 'input',
          name: 'title',
          message: __('enterTitle'),
        });
      }
      if (!reviewer) {
        const reviewerChoices: UserSelectChoice[] = [];
        const defaultReviewerIds: string[] = [];
        if (defaultReviewers?.length) {
          defaultReviewers.forEach((r) => {
            reviewerChoices.push({
              name: r.username,
              value: `${r.id}`,
            });
            defaultReviewerIds.push(`${r.id}`);
          });
        }
        questions.push({
          type: 'checkbox-plus',
          name: 'reviewers',
          message: __('selectReviewers'),
          pageSize: 10,
          highlight: false,
          searchable: true,
          default: defaultReviewerIds,
          suffix: color.dim(__('selectTip')),
          source: async (answersSoFar: object, input: string) => {
            return this.apiService.getUserChoices(input, project, reviewerChoices);
          },
        });
      }
      const answers = await inquirer.prompt(questions);
      if (!title) {
        title = answers.title;
      }
      if (!description) {
        description = DEFAULT_DESC;
      }

      if (reviewer) {
        reviewerIds = await this.getReviewerIds(reviewer);
      } else {
        reviewerIds = answers.reviewers;
      }

      const createSpinner = ora().start(__('createReviewing'));
      try {
        const review = await this.apiService.createReview(
          projectId,
          data,
          onlyFilename,
          svnBase,
          title!,
          description,
          reviewerIds?.join(SEPARATOR) || '',
          tapdTickets,
          ccIds,
          author,
        );
        const url = getUrlWithAdTag(`https://${vars.host()}/${project.fullPath}/reviews/${review.iid}`);
        createSpinner.succeed(__('openCr', { url }));
      } catch (e: any) {
        debug(`create review failed: ${e}`);
        createSpinner.fail(__('createCrFailed'));
        if (getErrorMessage(e)) {
          console.log(getErrorMessage(e));
        }
      }
    } else {
      console.log(color.error(__('onlySvnSupported')));
    }
  }

  async quickSvnCr(
    path: string,
    projectId: number,
    projectPath: string,
    data: string,
    onlyFilename: boolean,
    svnBase: string,
    defaultReviewers: User[],
    inputReviewers?: User[],
    tapdTickets?: TapdTicketForm[],
    ccUserIds?: number[],
    author?: string,
    titleFlag?: string,
    desc?: string,
  ) {
    const index = path.lastIndexOf('/');
    const dirname = path.substring(index);
    const title = titleFlag ? titleFlag : `update ${dirname}`;
    const description = desc ? desc : DEFAULT_DESC;
    if (inputReviewers?.length) {
      defaultReviewers.push(...inputReviewers);
    }
    const reviewer = defaultReviewers.map((r) => r.username)?.join(SEPARATOR) || '';
    console.log(__('createQuickCr', { path }));
    console.log(__('title', { title }));
    console.log(__('description', { description }));
    console.log(__('reviewers', { reviewer }));
    const reviewerIds = defaultReviewers.map((r) => r.id)?.join(SEPARATOR);
    const createSpinner = ora().start(__('createReviewing'));
    try {
      const review = await this.apiService.createReview(
        projectId,
        data,
        onlyFilename,
        svnBase,
        title,
        description,
        reviewerIds,
        tapdTickets,
        ccUserIds,
        author,
      );
      const url = getUrlWithAdTag(`https://${vars.host()}/${projectPath}/reviews/${review.iid}`);
      createSpinner.succeed(__('openCr', { url }));
    } catch (e: any) {
      debug(`create review failed: ${e}`);
      createSpinner.fail(__('createCrFailed'));
      if (getErrorMessage(e)) {
        console.log(getErrorMessage(e));
      }
    }
  }

  async getTapdTicket(tapd: string) {
    const tapdModel = await this.apiService.getTapdRelModel(tapd);
    return [{ workspaceId: tapdModel.workspaceId, id: tapdModel.tapdId, type: tapdModel.tapdType }];
  }

  async getCcIds(cc: string) {
    const ccList = cc.split(',');
    const ccUsers = await this.apiService.searchUsers(ccList);
    return ccUsers?.map((user) => user.id);
  }

  async getReviewerIds(reviewer: string) {
    const reviewers = await this.apiService.searchUsers(reviewer.split(','));
    return reviewers?.map((user) => user.id);
  }

  async getReviewers(reviewer: string) {
    return await this.apiService.searchUsers(reviewer.split(','));
  }

  async getPreConfig(projectId: number, urls: string[]) {
    try {
      const config = await this.apiService.getPresetConfig(projectId, urls);
      const defaultReviewers: User[] = [];
      if (config.reviewers?.length) {
        defaultReviewers.push(...config.reviewers);
      }
      if (!config.fileOwners?.length) {
        return defaultReviewers;
      }

      config.fileOwners.forEach((configOwner) => {
        const owners = configOwner.fileOwners;
        if (owners?.length) {
          owners.forEach((owner) => {
            const reviewer = defaultReviewers.find((user) => user.username === owner.username);
            if (!reviewer) {
              defaultReviewers.push(owner.user);
            }
          });
        }
      });
      return defaultReviewers;
    } catch (e: any) {
      debug(`getPreConfig failed: ${e}`);
    }
    return [];
  }
}
