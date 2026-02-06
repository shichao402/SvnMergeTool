import BaseCommand from '../../base';
import ApiService from '../../api-service';
import { Flags, Args } from '@oclif/core';
import {
  color,
  getBackEndError,
  getCurrentRemote,
  git,
  logger,
  loginUser,
  Project4Detail,
  ProtectedBranch,
} from '@tencent/gongfeng-cli-base';
import { getUserChoices, isCurrentUserCanEditMr, isNumeric, SEPARATOR } from '../../util';
import { MergeRequest4Detail, MergeRequestParams, MergeRequestState, UserSelectChoice } from '../../type';
import Debug from 'debug';
import * as inquirer from 'inquirer';
// @ts-ignore
import * as CheckboxPlus from 'inquirer-checkbox-plus-prompt';
import * as ora from 'ora';
import { Reviewer, CertifiedReviewerType, Review, ReviewState } from '@tencent/gongfeng-cli-base/dist/gong-feng';

inquirer.registerPrompt('checkbox-plus', CheckboxPlus);

const debug = Debug('gongfeng-mr:edit');
const TITLE_TYPE = 'title';
const DESCRIPTION_TYPE = 'description';
const REVIEWER_TYPE = 'reviewer';
const NECESSSARY_TYPE = 'necessary';

/**
 * 编辑合并请求命令
 */
export default class Edit extends BaseCommand {
  static summary = '编辑合并请求';
  static examples = [
    'gf mr edit 123 --title "edit merge request title" --description "edit merge request description"',
    'gf mr edit master --add-reviewer jack,rose --rm-reviewer alex',
  ];
  static usage = 'mr edit <iidOrBranch> [flags]';

  static args = {
    iidOrBranch: Args.string({
      required: true,
      description: '合并请求 id 或者源分支名称',
    }),
  };

  static flags = {
    title: Flags.string({
      char: 't',
      description: '设置新的标题',
    }),
    description: Flags.string({
      char: 'd',
      description: '设置新的描述',
    }),
    'add-reviewer': Flags.string({
      char: 'z',
      description: '添加评审人，可以添加多个评审人，使用英文逗号(,)分割',
    }),
    'add-necessary': Flags.string({
      char: 'x',
      description: '添加必要评审人，可以添加多个必要评审人，使用英文逗号(,)分割',
    }),
    'rm-reviewer': Flags.string({
      char: 'c',
      description: '删除评审人，可以删除多个评审人 , 使用英文逗号(,)分割',
    }),
    'rm-necessary': Flags.string({
      char: 'v',
      description: '删除必要评审人，可以删除多个必要评审人 , 使用英文逗号(,)分割',
    }),
    repo: Flags.string({
      char: 'R',
      description: '指定仓库，参数值使用“namespace/repo”的格式',
      required: false,
    }),
  };

  apiService!: ApiService;
  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { args, flags } = await this.parse(Edit);
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

    const fetchProjectDetailSpinner = ora().start(__('fetchProjectDetail'));
    const targetProject = await this.apiService.getProjectDetail(targetProjectPath);
    fetchProjectDetailSpinner.stop();
    if (!targetProject) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    const branch = args.iidOrBranch;
    const fetchMergeRequest4DetailSpinner = ora().start(__('fetchMergeRequestDetail'));
    let mergeRequest4Detail;
    if (isNumeric(branch)) {
      const iid = parseInt(branch, 10);
      mergeRequest4Detail = await this.apiService.getMergeRequestByIid(targetProject.id, iid);
    }

    if (!mergeRequest4Detail) {
      const mergeRequests = await this.apiService.searchLatestMergeRequestBySourceBranch(targetProject.id, branch);
      if (mergeRequests?.length) {
        const [mergeRequestFacade] = mergeRequests;
        mergeRequest4Detail = await this.apiService.getMergeRequestByIid(
          targetProject.id,
          mergeRequestFacade.mergeRequest.iid,
        );
      }
    }
    fetchMergeRequest4DetailSpinner.stop();

    if (!mergeRequest4Detail) {
      console.log(color.warn(__('noMergeRequests', { projectPath: targetProjectPath })));
      this.exit(0);
      return;
    }

    if (!isCurrentUserCanEditMr(mergeRequest4Detail)) {
      console.log(color.error(__('noPermissionUpdateMr')));
      this.exit(0);
      return;
    }

    if (!this.isMrOpen(mergeRequest4Detail)) {
      console.log(color.error(__('onlyOpenMrCanUpdate')));
      this.exit(0);
      return;
    }

    const {
      title,
      description,
      'add-reviewer': addReviewers,
      'add-necessary': addNReviewers,
      'rm-reviewer': rmReviewers,
      'rm-necessary': rmNReviewers,
    } = flags;

    const isAnyFlagExist = title || description || addReviewers || addNReviewers || rmNReviewers || rmReviewers;

    const reviewers = mergeRequest4Detail.review.reviewers.filter(
      (r: Reviewer) => r.type === CertifiedReviewerType.SUGGESTION || r.type === CertifiedReviewerType.INVITE,
    );
    const reviewerIds = reviewers.map((u) => u.userId);
    const necessaryReviewers = mergeRequest4Detail.review.reviewers.filter(
      (r: Reviewer) => r.type === CertifiedReviewerType.NECESSARY,
    );
    const necessaryIds = necessaryReviewers.map((u) => u.userId);
    if (isAnyFlagExist) {
      if (title || description) {
        const result = await this.updateTitleOrDesc(title, description, targetProject, mergeRequest4Detail);
        if (!result) {
          this.updateFailed();
          return;
        }
      }

      const isUpdateReviewer = addReviewers || addNReviewers || rmNReviewers || rmReviewers;

      if (isUpdateReviewer) {
        await this.updateReviewer(
          mergeRequest4Detail,
          targetProject,
          reviewerIds,
          necessaryIds,
          addReviewers,
          addNReviewers,
          rmReviewers,
          rmNReviewers,
        );
      }
      console.log(`\n ${color.success(__('updateMrSuccess'))}`);
    } else {
      if (!process.stdin.isTTY) {
        console.log(color.error(__('ttyNotSupport')));
        this.exit(0);
        return;
      }
      await this.updateMergeRequestInteractive(
        targetProject,
        mergeRequest4Detail,
        reviewers,
        necessaryReviewers,
        reviewerIds,
        necessaryIds,
      );
      console.log(`\n ${color.success(__('updateMrSuccess'))}`);
    }
  }

  async updateTitleOrDesc(
    title: string | undefined,
    description: string | undefined,
    targetProject: Project4Detail,
    mergeRequest4Detail: MergeRequest4Detail,
  ) {
    const params: Partial<MergeRequestParams> = {};
    if (title) {
      params.title = title;
    }
    if (description) {
      params.description = description;
    }
    return await this.apiService.updateMergeRequest(targetProject.id, mergeRequest4Detail.mergeRequest.iid, params);
  }

  async updateReviewer(
    mergeRequest4Detail: MergeRequest4Detail,
    targetProject: Project4Detail,
    reviewerIds: number[],
    necessaryIds: number[],
    addReviewers?: string,
    addNReviewers?: string,
    rmReviewers?: string,
    rmNReviewers?: string,
  ) {
    if (!this.canEditReviewer(mergeRequest4Detail)) {
      console.log(color.error(__('canNotEditReviewer')));
      this.exit(0);
      return;
    }
    const config = await this.apiService.getBranchConfig(
      targetProject.id,
      mergeRequest4Detail.mergeRequest.targetBranch,
    );
    const currentUser = await loginUser();
    const [needReviewerIds, needNecessaryIds] = await this.getNeedUpdateReviewerIds(
      targetProject,
      config,
      currentUser,
      reviewerIds,
      necessaryIds,
      addReviewers,
      addNReviewers,
      rmReviewers,
      rmNReviewers,
    );

    await this.updateReviewers(targetProject.id, mergeRequest4Detail.review.iid, needReviewerIds, needNecessaryIds);
  }

  async getNeedUpdateReviewerIds(
    project: Project4Detail,
    config: ProtectedBranch,
    currentUser: string,
    reviewerIds: number[],
    necessaryIds: number[],
    addReviewers?: string,
    addNReviewers?: string,
    rmReviewers?: string,
    rmNReviewers?: string,
  ): Promise<[number[], number[]]> {
    let addUsernames = addReviewers ? addReviewers.trim().split(SEPARATOR) : [];
    const [validUsernames, invalidUsernames] = await this.getValidUsernames(project, addUsernames);
    if (invalidUsernames.length) {
      console.log(color.error(__('invalidReviewers', { users: invalidUsernames.join(SEPARATOR) })));
    }
    addUsernames = validUsernames;
    let addNUsernames = addNReviewers ? addNReviewers.trim().split(SEPARATOR) : [];
    const [validNUsernames, invalidNUsernames] = await this.getValidUsernames(project, addNUsernames);
    if (invalidNUsernames.length) {
      console.log(color.error(__('invalidNReviewers', { users: invalidNUsernames.join(SEPARATOR) })));
    }
    addNUsernames = validNUsernames;
    if (!config.canApproveByCreator) {
      const currentReviewer =
        addUsernames.find((username) => username === currentUser) ||
        addNUsernames.find((username) => username === currentUser);
      if (currentReviewer) {
        console.log(color.warn(__('canNotApproveBySelf')));
      }
      addUsernames = addUsernames.filter((username) => username !== currentUser);
      addNUsernames = addNUsernames.filter((username) => username !== currentUser);
    }
    const rmUsernames = rmReviewers ? rmReviewers.trim().split(SEPARATOR) : [];
    const rmNUsernames = rmNReviewers ? rmNReviewers.trim().split(SEPARATOR) : [];
    const users = await this.apiService.searchUsers([
      ...addUsernames,
      ...addNUsernames,
      ...rmUsernames,
      ...rmNUsernames,
    ]);
    const addUserIds = users
      .filter((u) => addUsernames.findIndex((username) => username === u.username) >= 0)
      .map((user) => user.id);
    const addNUserIds = users
      .filter((u) => addNUsernames.findIndex((username) => username === u.username) >= 0)
      .map((user) => user.id);
    const rmUserIds = users
      .filter((u) => rmUsernames.findIndex((username) => username === u.username) >= 0)
      .map((user) => user.id);
    const rmNUserIds = users
      .filter((u) => rmNUsernames.findIndex((username) => username === u.username) >= 0)
      .map((user) => user.id);
    addUserIds.forEach((id) => {
      if (reviewerIds.findIndex((rid) => rid === id) < 0) {
        reviewerIds.push(id);
      }
    });
    rmUserIds.forEach((id) => {
      const index = reviewerIds.findIndex((rid) => rid === id);
      if (index >= 0) {
        reviewerIds.splice(index, 1);
      }
    });
    addNUserIds.forEach((id) => {
      if (necessaryIds.findIndex((rid) => rid === id) < 0) {
        necessaryIds.push(id);
      }
    });
    rmNUserIds.forEach((id) => {
      const index = necessaryIds.findIndex((rid) => rid === id);
      if (index >= 0) {
        necessaryIds.splice(index, 1);
      }
    });
    return [reviewerIds, necessaryIds];
  }

  async getValidUsernames(project: Project4Detail, usernames: string[]) {
    const validUsernames = [];
    const invalidUsernames = [];
    for (const username of usernames) {
      const user = await this.apiService.getProjectMember(project, username);
      if (user) {
        validUsernames.push(username);
      } else {
        invalidUsernames.push(username);
      }
    }
    return [validUsernames, invalidUsernames];
  }

  async updateReviewers(projectId: number, reviewIid: number, reviewerIds?: number[], necessaryIds?: number[]) {
    try {
      await this.apiService.batchSubmitReviewers(projectId, reviewIid, reviewerIds, necessaryIds);
    } catch (e: any) {
      console.log(color.error(__('updateReviewerError')));
      const error = getBackEndError(e);
      logger.error('update reviewer error', e);
      if (error) {
        console.log(color.error(error.message));
        debug(`trace: ${error.trace}`);
      } else {
        console.log(e.message);
      }
    }
  }

  async selectUpdateType() {
    const answers = await inquirer.prompt({
      type: 'list',
      name: 'type',
      message: __('selectEditType'),
      choices: [
        {
          name: __('title'),
          value: TITLE_TYPE,
        },
        {
          name: __('description'),
          value: DESCRIPTION_TYPE,
        },
        {
          name: __('reviewer'),
          value: REVIEWER_TYPE,
        },
        {
          name: __('necessaryReviewer'),
          value: NECESSSARY_TYPE,
        },
      ],
    });
    return answers.type;
  }

  async updateTitle(projectId: number, iid: number, title: string) {
    const titleAnswers = await inquirer.prompt({
      type: 'input',
      name: 'title',
      message: __('enterTitle'),
      default: title,
    });
    const newTitle = titleAnswers.title;
    const result = await this.apiService.updateMergeRequest(projectId, iid, {
      title: newTitle,
    });
    if (!result) {
      this.updateFailed();
      return;
    }
  }

  async updateDescription(projectId: number, iid: number, desc: string) {
    const descAnswers = await inquirer.prompt({
      type: 'editor',
      name: 'description',
      message: __('enterDescription'),
      default: desc,
    });
    const newDesc = descAnswers.description;
    const result = await this.apiService.updateMergeRequest(projectId, iid, {
      description: newDesc,
    });
    if (!result) {
      this.updateFailed();
      return;
    }
  }

  async updateNormalReviewers(
    project: Project4Detail,
    config: ProtectedBranch,
    choices: UserSelectChoice[],
    defaultChoice: string[],
    currentUser: string,
    reviewIid: number,
    necessaryIds: number[],
  ) {
    const question = {
      type: 'checkbox-plus',
      name: 'reviewers',
      message: __('selectReviewers'),
      pageSize: 10,
      highlight: false,
      searchable: true,
      default: defaultChoice,
      suffix: color.dim(__('selectTip')),
      source: async (answersSoFar: object, input: string) => {
        return this.apiService.getUserChoices(input, project, config, choices, currentUser);
      },
    };
    const reviewerAnswers = await inquirer.prompt([question]);
    const reviewerIds = reviewerAnswers.reviewers;
    await this.updateReviewers(project.id, reviewIid, reviewerIds, necessaryIds);
  }

  async updateNecessaryReviewers(
    project: Project4Detail,
    config: ProtectedBranch,
    choices: UserSelectChoice[],
    defaultChoice: string[],
    currentUser: string,
    reviewIid: number,
    reviewerIds: number[],
  ) {
    const question = {
      type: 'checkbox-plus',
      name: 'necessary',
      message: __('selectReviewers'),
      pageSize: 10,
      highlight: false,
      searchable: true,
      default: defaultChoice,
      suffix: color.dim(__('selectTip')),
      source: async (answersSoFar: object, input: string) => {
        return this.apiService.getUserChoices(input, project, config, choices, currentUser);
      },
    };
    const necessaryAnswers = await inquirer.prompt([question]);
    const necessaryIds = necessaryAnswers.necessary;
    await this.updateReviewers(project.id, reviewIid, reviewerIds, necessaryIds);
  }

  async updateMergeRequestInteractive(
    targetProject: Project4Detail,
    mergeRequest4Detail: MergeRequest4Detail,
    reviewers: Reviewer[],
    necessaryReviewers: Reviewer[],
    reviewerIds: number[],
    necessaryIds: number[],
  ) {
    const answersType = await this.selectUpdateType();
    if (answersType === TITLE_TYPE || answersType === DESCRIPTION_TYPE) {
      if (answersType === TITLE_TYPE) {
        await this.updateTitle(
          targetProject.id,
          mergeRequest4Detail.mergeRequest.iid,
          mergeRequest4Detail.mergeRequest.titleRaw,
        );
      }
      if (answersType === DESCRIPTION_TYPE) {
        await this.updateDescription(
          targetProject.id,
          mergeRequest4Detail.mergeRequest.iid,
          mergeRequest4Detail.mergeRequest.descriptionRaw,
        );
      }
    } else {
      if (!this.canEditReviewer(mergeRequest4Detail)) {
        console.log(color.error(__('canNotEditReviewer')));
        this.exit(0);
        return;
      }
      const config = await this.apiService.getBranchConfig(
        targetProject.id,
        mergeRequest4Detail.mergeRequest.targetBranch,
      );
      const currentUser = await loginUser();
      const [reviewerChoices, reviewerDefault] = getUserChoices(reviewers);
      const [necessaryChoices, necessaryDefault] = getUserChoices(necessaryReviewers);

      if (answersType === REVIEWER_TYPE) {
        await this.updateNormalReviewers(
          targetProject,
          config,
          reviewerChoices,
          reviewerDefault,
          currentUser,
          mergeRequest4Detail.review.iid,
          necessaryIds,
        );
      }
      if (answersType === NECESSSARY_TYPE) {
        await this.updateNecessaryReviewers(
          targetProject,
          config,
          necessaryChoices,
          necessaryDefault,
          currentUser,
          mergeRequest4Detail.review.iid,
          reviewerIds,
        );
      }
    }
  }

  updateFailed() {
    console.log(color.error(__('updateMrError')));
    this.exit(0);
    return;
  }

  isMrOpen(mergeRequest4Detail: MergeRequest4Detail) {
    return (
      mergeRequest4Detail.mergeRequest.state === MergeRequestState.OPENED ||
      mergeRequest4Detail.mergeRequest.state === MergeRequestState.REOPENED
    );
  }

  isMrUpdateAble(mergeRequest4Detail: MergeRequest4Detail) {
    return (
      mergeRequest4Detail.mergeRequest?.state !== MergeRequestState.MERGED &&
      mergeRequest4Detail.mergeRequest?.state !== MergeRequestState.CLOSED
    );
  }

  isReviewEditable(review: Review) {
    return (
      review.state !== ReviewState.APPROVED &&
      review.state !== ReviewState.CLOSED &&
      review.state !== ReviewState.CHANGE_DENIED &&
      review.state !== ReviewState.CHANGE_REQUIRED
    );
  }

  canEditReviewer(mergeRequest4Detail: MergeRequest4Detail) {
    return (
      isCurrentUserCanEditMr(mergeRequest4Detail) &&
      this.isMrUpdateAble(mergeRequest4Detail) &&
      this.isReviewEditable(mergeRequest4Detail.review)
    );
  }
}
