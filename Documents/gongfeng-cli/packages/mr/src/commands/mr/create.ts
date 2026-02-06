import { Flags } from '@oclif/core';
import BaseCommand from '../../base';
import {
  color,
  Remote,
  vars,
  Project4Detail,
  getCurrentRemote,
  getSourceRemote,
  loginUser,
  getBackEndError,
  ProtectedBranch,
  git,
  Rules,
  logger,
  cloneTokenCompo,
  AutocompleteUser,
  getUrlWithAdTag,
} from '@tencent/gongfeng-cli-base';
import ApiService from '../../api-service';
import { getDefaultDescription, getUserChoices, SEPARATOR, validUrl } from '../../util';
import Debug from 'debug';
import * as inquirer from 'inquirer';
// @ts-ignore
import * as CheckboxPlus from 'inquirer-checkbox-plus-prompt';
import * as qs from 'qs';
import { CertifiedReviewer } from '../../type';
import * as ora from 'ora';
import * as open from 'open';
import { Commit } from '@tencent/gongfeng-cli-base/dist/models';

inquirer.registerPrompt('checkbox-plus', CheckboxPlus);
const debug = Debug('gongfeng-mr:create');

const CONFIRM = '1';
const CANCEL = '0';

/**
 * 创建合并请求命令
 */
export default class Create extends BaseCommand {
  static summary = '创建合并请求';
  static description = `没有指定源分支时，会默认将当前分支的更改推送至远程跟踪分支，然后发起与目标分支的合并请求。
命令行默认会通过问答的模式引导填写信息，同时带-t和-d参数时会跳过问答模式直接发起MR。使用-q可以使用默认信息快速创建合并请求，使用-w参数可以打开浏览器创建合并请求。`;
  static examples = [
    'gf mr create',
    'gf mr create -q',
    'gf mr create --title "merge request title" --description "merge request description"',
  ];
  static usage = 'mr create [flags]';

  static flags = {
    title: Flags.string({
      char: 't',
      description: '合并请求标题',
    }),
    description: Flags.string({
      char: 'd',
      description: '合并请求描述',
    }),
    target: Flags.string({
      char: 'T',
      description: '目标分支（默认为仓库的默认分支）',
    }),
    source: Flags.string({
      char: 's',
      description: '源分支（默认为当前分支）',
    }),
    reviewer: Flags.string({
      char: 'r',
      description: '通过用户名指定评审人，使用英文逗号(,)分割',
    }),
    'necessary-reviewer': Flags.string({
      char: 'n',
      description: '通过用户名指定必要评审人，使用英文逗号(,)分割',
    }),
    quick: Flags.boolean({
      char: 'q',
      description: '快速发起合并请求，所有字段使用默认值',
    }),
    web: Flags.boolean({
      char: 'w',
      description: '打开浏览器创建合并请求',
    }),
    repo: Flags.string({
      char: 'R',
      description: '指定仓库，参数值使用“namespace/repo”格式',
      required: false,
    }),
  };

  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { flags } = await this.parse(Create);
    const currentPath = process.cwd();

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
      this.exit();
      return;
    }

    // 由于这次请求结束到下次输出之间还有多次异步请求，且同属获取醒目详细信息，因此中间任意一次退出都需要先结束此 spinner
    const fetchProjectDetailSpinner = ora().start(__('fetchProjectDetail'));
    const targetProject = await this.apiService.getProjectDetail(targetProjectPath);
    if (!targetProject) {
      fetchProjectDetailSpinner.stop();
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    const userSession = await this.apiService.getCurrentUser(`${targetProject.id}`);
    if (userSession.permissions.indexOf(Rules.CREATE_MERGE_REQUEST) < 0) {
      fetchProjectDetailSpinner.stop();
      console.log(color.error(__('noPermissionCreateMr')));
      this.exit(0);
      return;
    }

    let sourceBranch = flags.source;
    let sourceBranchLabel = sourceBranch;
    if (!sourceBranch) {
      sourceBranch = (await git.getCurrentBranch(currentPath)) || '';
      if (!sourceBranch) {
        fetchProjectDetailSpinner.stop();
        console.log(color.error(__('determineCurrentBranch')));
        this.exit(0);
        return;
      }
      sourceBranchLabel = sourceBranch;
    }

    await this.warnUnCommittedFiles(currentPath);

    let sourceProject: Project4Detail | null = null;
    let sourceRemote: Remote | undefined = undefined;

    // determine whether the source branch is already pushed to a remote
    const pushTo = await git.determineTrackingBranch(currentPath, sourceBranch);
    if (pushTo) {
      const remotes = await git.getRemotes(currentPath);
      const remote = remotes.find((r: Remote) => r.name === pushTo.remoteName);
      if (remote) {
        sourceRemote = remote;
        sourceBranchLabel = pushTo.branchName;
        debug(`already pushTo remote: ${remote.name}, branch name: ${pushTo.branchName}`);
      }
    }

    if (!sourceRemote) {
      sourceRemote = await getSourceRemote(currentPath);
    }

    if (!sourceRemote) {
      fetchProjectDetailSpinner.stop();
      console.log(color.error(__('projectSourceRemoteNotFound')));
      this.exit(0);
      return;
    }

    const sourceProjectPath = (await git.projectPathFromRemote(currentPath, sourceRemote.name)) ?? '';
    if (!sourceProjectPath) {
      fetchProjectDetailSpinner.stop();
      console.log(`${color.error(__('sourceProjectNotFound', { sourceProjectPath }))}`);
      this.exit(0);
      return;
    }

    sourceProject =
      sourceProjectPath === targetProjectPath
        ? targetProject
        : await this.apiService.getProjectDetail(sourceProjectPath);
    if (!sourceProject) {
      fetchProjectDetailSpinner.stop();
      console.log(`${color.error(__('sourceProjectNotFound', { sourceProjectPath }))}`);
      this.exit(0);
      return;
    }

    const sourceProjectPushUrl = `https://${await cloneTokenCompo()}@${vars.host()}/${sourceProject.fullPath}.git`;

    if (sourceProject.id !== targetProject.id) {
      sourceBranchLabel = `${sourceProject.fullPath}:${sourceBranchLabel}`;
    }

    fetchProjectDetailSpinner.stop();
    let { target: targetBranch } = flags;
    const { title, description } = flags;
    if (!targetBranch) {
      if (flags.web || flags.quick || (title && description)) {
        targetBranch = targetProject.defaultBranch;
      } else {
        targetBranch = await this.getTargetBranch(targetProject);
      }
    }
    if (!targetBranch) {
      console.log(color.error(__('targetBranchNotFound')));
      this.exit(0);
      return;
    }

    sourceBranch = sourceBranch.trim();
    targetBranch = targetBranch.trim();
    if (sourceBranch === targetBranch && sourceProject.id === targetProject.id) {
      console.log(color.error(__('sameBranch')));
      this.exit(0);
      return;
    }

    // 校验 MR 是否已经存在，若已存在则方法中会直接退出
    await this.checkSimilarMergeRequests(targetProject.id, sourceProject.id, targetBranch, sourceBranch);
    let targetTrackingBranch = targetBranch;
    if (targetRemote) {
      targetTrackingBranch = `${targetRemote.name}/${targetBranch}`;
    }

    debug(`sourceBranch:${sourceBranch}`);
    debug(`targetBranch:${targetBranch}`);
    debug(`sourceProjectPath:${sourceProject.fullPath}`);
    debug(`targetProjectPath:${targetProject.fullPath}`);
    debug(`sourceBranchLabel:${sourceBranchLabel}`);
    debug(`targetTrackingBranch:${targetTrackingBranch}`);
    debug(`sourcePushUrl: ${sourceProjectPushUrl}`);

    const commits = await git.getCommits(currentPath, git.revRange(targetTrackingBranch, sourceBranch), 120);
    if (!commits?.length) {
      console.log(color.error(__('noCommitsFound', { sourceBranch, targetBranch: targetTrackingBranch })));
      this.exit(0);
      return;
    }

    if (flags.web) {
      await this.openWithBrowser(
        currentPath,
        flags.title,
        flags.description,
        sourceRemote,
        sourceProjectPushUrl,
        sourceBranch,
        targetBranch,
        sourceProject,
        targetProject,
      );
      return;
    }

    const currentUser = await loginUser();
    let { reviewers, necessaryReviewers } = await this.apiService.getDefaultReviewers(
      targetProject.id,
      targetBranch,
      sourceBranch,
      sourceBranch,
      targetBranch,
      sourceProject.id,
    );

    const config = await this.apiService.getBranchConfig(targetProject.id, targetBranch);
    if (!config.canApproveByCreator) {
      this.warnApproveBySelf(currentUser, reviewers, necessaryReviewers);
      reviewers = reviewers.filter((reviewer) => reviewer.user.username !== currentUser);
      necessaryReviewers = necessaryReviewers.filter((reviewer) => reviewer.user.username !== currentUser);
    }

    const { 'necessary-reviewer': necessary } = flags;
    if (flags.quick || (title && description)) {
      await this.quickMergeRequest(
        flags.reviewer,
        targetProject,
        config,
        currentUser,
        reviewers,
        necessaryReviewers,
        necessary,
        currentPath,
        sourceRemote,
        sourceProjectPushUrl,
        sourceBranch,
        sourceBranchLabel,
        targetBranch,
        targetProjectPath,
        title,
        description,
        sourceProject,
      );
      return;
    }

    if (!process.stdin.isTTY) {
      console.log(color.error(__('ttyNotSupport')));
      this.exit(0);
      return;
    }

    const result = await this.getUserInputValue(
      reviewers,
      necessaryReviewers,
      title,
      description,
      flags.reviewer,
      necessary,
      commits,
      targetProject,
      config,
      currentUser,
      sourceBranch,
    );

    await this.handlePush(currentPath, sourceRemote, sourceProjectPushUrl, sourceBranch);
    const confirmResult = await this.secondaryConfirm();
    if (confirmResult === CONFIRM) {
      await this.handleCreateMergeRequest(
        targetProject,
        sourceProject,
        result.title,
        targetBranch,
        sourceBranch,
        config,
        result.reviewerIds,
        result.necessaryIds,
        result.description,
      );
    }
  }

  async quickMergeRequest(
    flagReviewer: string | undefined,
    targetProject: Project4Detail,
    config: ProtectedBranch,
    currentUser: string,
    reviewers: CertifiedReviewer[],
    necessaryReviewers: CertifiedReviewer[],
    necessary: string | undefined,
    currentPath: string,
    sourceRemote: Remote,
    sourceProjectPushUrl: string,
    sourceBranch: string,
    sourceBranchLabel: string | undefined,
    targetBranch: string,
    targetProjectPath: string,
    title: string | undefined,
    description: string | undefined,
    sourceProject: Project4Detail,
  ) {
    if (flagReviewer) {
      const res = await this.getInputReviewers(flagReviewer, targetProject, config, 'invalidReviewers', currentUser);
      res.forEach((r) => {
        reviewers.push({ user: r });
      });
    }
    if (necessary) {
      const reviewers = await this.getInputReviewers(
        necessary,
        targetProject,
        config,
        'invalidNReviewers',
        currentUser,
      );
      reviewers.forEach((r) => {
        necessaryReviewers.push({ user: r });
      });
    }
    const reviewerIds = reviewers.map((r) => r.user.id);
    const reviewerUserNames = reviewers.map((r) => r.user.username);
    const necessaryReviewerIds = necessaryReviewers.map((r) => r.user.id);
    const necessaryUserNames = necessaryReviewers.map((r) => r.user.username);
    await this.handlePush(currentPath, sourceRemote, sourceProjectPushUrl, sourceBranch);
    console.log(
      `\n${color.bold(
        __('createMergeRequest', {
          sourceBranch: sourceBranchLabel || sourceBranch || '',
          targetBranch: targetBranch || '',
          targetProjectPath: targetProjectPath || '',
        }),
      )}`,
    );
    if (!title) {
      title = sourceBranch;
    }
    console.log(`${color.bold(__('title'))}: ${title}`);
    console.log(`${color.bold(__('description'))}: ${description || ''}`);
    console.log(`${color.bold(__('reviewers'))} ${reviewerUserNames.join(', ')}`);
    console.log(`${color.bold(__('necessaryReviewers'))} ${necessaryUserNames.join(', ')}`);
    await this.handleCreateMergeRequest(
      targetProject,
      sourceProject,
      title,
      targetBranch,
      sourceBranch,
      config,
      reviewerIds,
      necessaryReviewerIds,
      description,
    );
  }

  async getUserInputValue(
    reviewers: CertifiedReviewer[],
    necessaryReviewers: CertifiedReviewer[],
    flagTitle: string | undefined,
    flagDesc: string | undefined,
    flagReviewer: string | undefined,
    necessary: string | undefined,
    commits: ReadonlyArray<Commit>,
    targetProject: Project4Detail,
    config: ProtectedBranch,
    currentUser: string,
    sourceBranch: string,
  ) {
    const [reviewerChoices, reviewerDefault] = getUserChoices(reviewers);
    const [necessaryChoices, necessaryDefault] = getUserChoices(necessaryReviewers);
    let inputReviewerIds: number[] = [];
    let inputNecessaryIds: number[] = [];
    const questions = [];
    if (!flagTitle) {
      const latestCommit = commits[0];
      const message = latestCommit.summary;
      questions.push({
        type: 'input',
        name: 'title',
        message: __('enterTitle'),
        default: message,
      });
    }

    if (!flagDesc) {
      const latestCommit = commits[0];
      questions.push({
        type: 'editor',
        name: 'description',
        message: __('enterDescription'),
        default: getDefaultDescription(config, `${latestCommit.summary}\n${latestCommit.body}`),
      });
    }

    if (!flagReviewer) {
      questions.push({
        type: 'checkbox-plus',
        name: 'reviewers',
        message: __('selectReviewers'),
        pageSize: 10,
        highlight: false,
        searchable: true,
        default: reviewerDefault,
        suffix: color.dim(__('selectTip')),
        source: async (answersSoFar: object, input: string) => {
          return this.apiService.getUserChoices(input, targetProject, config, reviewerChoices, currentUser);
        },
      });
    } else {
      const reviewers = await this.getInputReviewers(
        flagReviewer,
        targetProject,
        config,
        'invalidReviewers',
        currentUser,
      );
      inputReviewerIds = reviewers.map((u) => u.id);
    }

    if (!necessary) {
      questions.push({
        type: 'checkbox-plus',
        name: 'necessary',
        message: __('selectNecessaryReviewers'),
        pageSize: 10,
        highlight: false,
        searchable: true,
        default: necessaryDefault,
        suffix: color.dim(__('selectTip')),
        source: async (answersSoFar: object, input: string) => {
          return this.apiService.getUserChoices(input, targetProject, config, necessaryChoices, currentUser);
        },
      });
    } else {
      const reviewers = await this.getInputReviewers(
        necessary,
        targetProject,
        config,
        'invalidNReviewers',
        currentUser,
      );
      inputNecessaryIds = reviewers.map((u) => u.id);
    }

    const answers = await inquirer.prompt(questions);
    let { title } = answers;
    if (!title) {
      title = flagTitle ?? sourceBranch;
    }
    let { description } = answers;
    if (!description) {
      description = flagDesc ?? '';
    }
    let reviewerIds = answers.reviewers;
    if (!reviewerIds?.length) {
      reviewerIds = inputReviewerIds;
    }
    let necessaryIds = answers.necessary;
    if (!necessaryIds?.length) {
      necessaryIds = inputNecessaryIds;
    }
    return {
      title,
      description,
      reviewerIds,
      necessaryIds,
    };
  }

  warnApproveBySelf(currentUser: string, reviewers: CertifiedReviewer[], necessaryReviewers: CertifiedReviewer[]) {
    const currentReviewer =
      reviewers.find((reviewer) => reviewer.user.username === currentUser) ||
      necessaryReviewers.find((reviewer) => reviewer.user.username === currentUser);
    if (currentReviewer) {
      console.log(color.warn(__('canNotApproveBySelf')));
    }
  }

  async openWithBrowser(
    currentPath: string,
    flagTitle: string | undefined,
    flagDesc: string | undefined,
    sourceRemote: Remote,
    sourceProjectPushUrl: string,
    sourceBranch: string,
    targetBranch: string,
    sourceProject: Project4Detail,
    targetProject: Project4Detail,
  ) {
    await this.handlePush(currentPath, sourceRemote, sourceProjectPushUrl, sourceBranch);
    const params = {
      title: flagTitle,
      sourceBranch,
      targetBranch,
      sourceProjectId: sourceProject.id,
      targetProjectId: targetProject.id,
      description: flagDesc,
    };
    const query = qs.stringify(params);
    const url = getUrlWithAdTag(`https://${vars.host()}/${targetProject.fullPath}/merge_requests/new?${query}`);
    if (!validUrl(url)) {
      console.log(color.error(__('urlTooLong')));
      this.exit(0);
      return;
    }
    console.log(__('openBrowser', { url }));
    try {
      await open(url);
    } catch (e) {
      console.log(color.error(__('openBrowserFailed')));
    }
  }

  async warnUnCommittedFiles(currentPath: string) {
    const status = await git.getStatus(currentPath);
    if (status?.workingDirectory?.files?.length) {
      console.log(color.warn(__n('%s uncommitted changed file', status.workingDirectory.files.length)));
    }
  }

  async getTargetBranch(targetProject: Project4Detail) {
    const answers = await inquirer.prompt({
      type: 'input',
      name: 'targetBranch',
      message: __('enterTargetBranch'),
      default: targetProject.defaultBranch,
    });
    return answers.targetBranch;
  }

  async handlePush(repoPath: string, sourceRemote: Remote, sourceUrl: string, sourceBranch: string) {
    await git.push2(repoPath, sourceRemote, sourceUrl, 'HEAD', sourceBranch, null);
  }

  async getInputReviewers(
    input: string,
    project: Project4Detail,
    config: ProtectedBranch,
    label: string,
    currentUser?: string,
  ): Promise<AutocompleteUser[]> {
    const [reviewers, invalidUsers] = await this.filterInputReviewers(input, project, config, currentUser);
    if (invalidUsers.length) {
      console.log(color.error(__(label, { users: invalidUsers.join(SEPARATOR) })));
    }
    return reviewers;
  }

  async filterInputReviewers(
    input: string,
    project: Project4Detail,
    config: ProtectedBranch,
    currentUser?: string,
  ): Promise<[AutocompleteUser[], string[]]> {
    const invalidReviewers: AutocompleteUser[] = [];
    const invalidUsers: string[] = [];
    if (!input) {
      return [invalidReviewers, invalidUsers];
    }
    const reviewers = input.split(SEPARATOR).filter((reviewer) => {
      return !(!config.canApproveByCreator && reviewer === currentUser);
    });
    if (reviewers?.length) {
      for (const reviewer of reviewers) {
        const user = await this.apiService.getProjectMember(project, reviewer);
        if (user) {
          invalidReviewers.push(user);
        } else {
          invalidUsers.push(reviewer);
        }
      }
      return [invalidReviewers, invalidUsers];
    }
    return [invalidReviewers, invalidUsers];
  }

  async handleCreateMergeRequest(
    targetProject: Project4Detail,
    sourceProject: Project4Detail,
    title: string,
    targetBranch: string,
    sourceBranch: string,
    config: ProtectedBranch,
    reviewerIds: number[],
    necessaryReviewerIds: number[],
    description?: string,
  ) {
    try {
      const mergeRequest = await this.apiService.createMergeRequest(targetProject.id, {
        title,
        description,
        targetBranch,
        sourceBranch,
        targetProjectId: targetProject.id,
        sourceProjectId: sourceProject.id,
        approverRule: config.approverRule,
        approverRuleNumber: config.approverRule,
        necessaryApproverRule: config.necessaryApproverRule,
        necessaryApproverRuleNumber: config.necessaryApproverRule,
        reviewerIds: reviewerIds.join(SEPARATOR),
        necessaryReviewerIds: necessaryReviewerIds.join(SEPARATOR),
      });
      const url = getUrlWithAdTag(
        `https://${vars.host()}/${targetProject.fullPath}/merge_requests/${mergeRequest.iid}`,
      );
      console.log(`\n\n${color.gray(__('openUrl', { url }))}`);
    } catch (e: any) {
      logger.error('create mr error:', e);
      const error = getBackEndError(e);
      if (error) {
        console.log(color.error(error.message));
        debug(`trace: ${error.trace}`);
        logger.error(`create mr error trace: ${error.trace}`);
      } else {
        console.log(e.message);
      }
    }
  }

  async checkSimilarMergeRequests(
    targetProjectId: number,
    sourceProjectId: number,
    targetBranch: string,
    sourceBranch: string,
  ) {
    const similarMergeRequests = await this.apiService.getSimilarMergeRequests(
      targetProjectId,
      sourceProjectId,
      targetBranch,
      sourceBranch,
    );
    if (similarMergeRequests.length) {
      const mergeRequest = similarMergeRequests[0];
      console.log(color.error(__('mergeRequestExisted')));
      console.log(`[!${mergeRequest.iid}] ${mergeRequest.titleRaw}`);
      this.exit(0);
    }
  }

  async secondaryConfirm() {
    console.log('');
    const answer = await inquirer.prompt({
      type: 'list',
      name: 'confirm',
      message: __('confirmSubmit'),
      choices: [
        {
          name: __('confirm'),
          value: CONFIRM,
        },
        {
          name: __('cancel'),
          value: CANCEL,
        },
      ],
    });
    return answer.confirm;
  }
}
