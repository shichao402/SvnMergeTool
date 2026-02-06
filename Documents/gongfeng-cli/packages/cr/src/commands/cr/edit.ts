import { Flags, Args } from '@oclif/core';
import BaseCommand from '../../base';
import { shell, color } from '@tencent/gongfeng-cli-base';
import ApiService from '../../api-service';
import {
  AutocompleteUser,
  Project4Detail,
  ReviewState,
  Reviewer,
  User,
} from '@tencent/gongfeng-cli-base/dist/gong-feng';
import { ReviewFacade, SvnReviewCreatedForm } from '../../type';
import * as inquirer from 'inquirer';
import Debug from 'debug';
import { SEPARATOR, isCodeInLocal } from '../../util';
import * as ora from 'ora';
// @ts-ignore
import * as CheckboxPlus from 'inquirer-checkbox-plus-prompt';
inquirer.registerPrompt('checkbox-plus', CheckboxPlus);

const debug = Debug('gongfeng-cr:edit');

enum InteractiveSelectType {
  TITLE = 'title',
  DESCRIPTION = 'description',
  REVIEWER = 'reviewer',
  // NECESSARY_REVIEWER = 'necessaryReviewer',
  CC_USERS = 'cc',
}

export default class Edit extends BaseCommand {
  static summary = '编辑代码评审';
  static examples = ['gf cr edit 123 --title "edit code review title" --description "edit code review description"'];
  static usage = 'cr edit <iid> [flags]';

  static args = {
    iid: Args.integer({
      required: true,
      description: '代码评审 iid',
    }),
  };

  static flags = {
    title: Flags.string({
      char: 't',
      description: '设置新的标题',
      helpGroup: '公共参数',
    }),
    description: Flags.string({
      char: 'd',
      description: '设置新的描述',
      helpGroup: '公共参数',
    }),
    'add-reviewer': Flags.string({
      char: 'z',
      description: '添加评审人，可以添加多个评审人，使用英文逗号(,)分割',
      helpGroup: '公共参数',
    }),
    // 'add-necessary': Flags.string({
    //   char: 'x',
    //   description: '添加必要评审人，可以添加多个必要评审人，使用英文逗号(,)分割',
    // }),
    cc: Flags.string({
      char: 'c',
      description: '添加抄送人，可以添加多个抄送人，使用英文逗号(,)分割',
      helpGroup: 'SVN 代码评审参数',
    }),
  };

  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { args, flags } = await this.parse(Edit);
    const { iid } = args;
    // 获取当前文件夹的 svn 路径
    let path = process.cwd();
    path = path.replace(/\\/g, '/');
    debug(`path: ${path}`);
    const { title, description, 'add-reviewer': addReviewers, cc } = flags;

    if (shell.isSvnPath(path)) {
      // 获取项目详情
      const svnBase = shell.getSvnBaseUrl(path);
      debug(`svnBase: ${svnBase}`);
      const fetchSpinner = ora().start(__('fetchProjectDetail'));
      const project4Detail = await this.apiService.getSvnProject(svnBase);
      if (!project4Detail) {
        fetchSpinner.stop();
        console.log(color.error(__('projectNotFound')));
        return;
      }

      // 确认 iid 对应的代码评审存在
      const reviewFacade = await this.getReviewFacade(project4Detail.id, iid);
      if (!reviewFacade) {
        fetchSpinner.stop();
        console.log(color.error(__('reviewNotFound', { iid: `${iid}` })));
        this.exit();
        return;
      }

      // 确认代码评审是否为打开状态
      if (!this.isCrOpen(reviewFacade.state)) {
        fetchSpinner.stop();
        console.log(color.error(__('onlyOpenCrCanUpdate')));
        this.exit(0);
        return;
      }
      fetchSpinner.stop();

      // 是否有任何 flag 输入，如果有则直接更新代码评审
      const isAnyFlagExist = title || description || addReviewers || cc;
      if (isAnyFlagExist) {
        await this.updateReviewByFlags(project4Detail, reviewFacade, {
          title,
          description,
          // addNReviewers: addNReviewers ? addNReviewers.split(SEPARATOR) : [],
          addReviewers: addReviewers ? addReviewers.split(SEPARATOR) : [],
          cc: cc ? cc.split(SEPARATOR) : [],
        });
      } else {
        // 如果没有则走交互式更新
        // 如果不支持交互式更新，则直接退出
        if (!process.stdin.isTTY) {
          console.log(color.error(__('ttyNotSupport')));
          this.exit(0);
          return;
        }
        // 交互式更新
        await this.updateReviewInteractive(reviewFacade, project4Detail);
      }
      console.log(`\n ${color.success(__('updateCrSuccess'))}`);
    } else {
      console.log(color.error(__('onlySvnSupported')));
    }
  }

  /**
   * 获取评审详情
   * @param projectId
   * @param reviewIid
   * @returns
   */
  private async getReviewFacade(projectId: number, reviewIid: number) {
    try {
      const reviewFacade = this.apiService.getReviewFacade(projectId, reviewIid);
      return reviewFacade;
    } catch (e) {
      console.log(color.error(__('reviewNotFound', { iid: `${reviewIid}` })));
      this.exit();
      return;
    }
  }

  /**
   * 更新代码评审
   * @param reviewFacade
   * @param projectId
   * @param params
   * @returns
   */
  private async updateReview(reviewFacade: ReviewFacade, projectId: number, params: Partial<SvnReviewCreatedForm>) {
    const isLocal = isCodeInLocal(reviewFacade);
    debug(`isCodeInLocal: ${isLocal}`);
    const requestParams: Partial<SvnReviewCreatedForm> = {
      // 默认取 reviewFacade.titleRaw
      title: reviewFacade.titleRaw,
      description: reviewFacade.comparison?.descriptionRaw || reviewFacade.svnMergeRequest?.description,
      ...params,
    };
    return isLocal
      ? this.apiService.updateSvnReviewCodeInLocal(projectId, reviewFacade.reviewableIid, requestParams)
      : this.apiService.updateReview(projectId, reviewFacade.iid, requestParams);
  }

  private async updateReviewByFlags(
    targetProject: Project4Detail,
    reviewFacade: ReviewFacade,
    flags: {
      title?: string;
      description?: string;
      addReviewers: string[];
      // addNReviewers: string[];
      cc: string[];
    },
  ) {
    const { addReviewers, cc, title, description } = flags;
    // 获取原有的抄送人列表，不传 ccUserIds 后端会默认以空数组覆盖
    const ccUsers = await this.apiService.getReviewCCUsers(targetProject.id, reviewFacade.iid);
    /**
     * 初始化更新请求参数
     * title 默认使用 reviewFacade.titleRaw
     * description 默认使用 reviewFacade.comparison.descriptionRaw
     * 其余用户参数校验后添加
     * */
    const params: Partial<SvnReviewCreatedForm> = {
      title: title || reviewFacade.titleRaw,
      description: description || reviewFacade.comparison?.descriptionRaw || reviewFacade.svnMergeRequest?.description,
      ccUserIds: ccUsers.map((user) => user.id),
    };

    if (addReviewers.length) {
      // 获取已选择的评审人和必要评审人
      const { normalReviewers } = await this.apiService.getReviewConfig(targetProject.id, reviewFacade.iid);
      const normalReviewersUser = normalReviewers.map((reviewer) => reviewer.user);
      // 如果用户输入了评审人，则校验输入的评审人合法性
      if (addReviewers.length) {
        const validUsers = await this.validateProjectUserNames(targetProject, addReviewers, 'invalidReviewers');
        // 将合法的用户 id 添加到请求参数
        params.reviewerIds = [...validUsers, ...normalReviewersUser].map((user) => user.id).join(SEPARATOR);
      }
      // // 如果用户输入了必要评审人，则校验输入的必要评审人合法性
      // if (addNReviewers.length) {
      //   const validUsers = await this.validateProjectUserNames(targetProject, addNReviewers, 'invalidNReviewers');
      //   // 将合法的用户 id 添加到请求参数
      //   params.necessaryReviewerIds = [...validUsers, ...necessaryReviewers].map((user) => user.id).join(SEPARATOR);
      // }
    }
    // 如果用户输入了抄送人，则校验输入的抄送人合法性
    if (cc.length) {
      const validUsers = await this.validateProjectUserNames(targetProject, cc, 'invalidCcUsers');
      // 将合法的用户 id 添加到请求参数
      params.ccUserIds = [...validUsers, ...ccUsers].map((user) => user.id);
    }

    this.updateReview(reviewFacade, targetProject.id, params);
  }

  /**
   * 交互式更新标题
   * @param reviewFacade
   * @param projectId
   * @returns
   */
  private async updateTitleInteractive(reviewFacade: ReviewFacade, projectId: number, ccUserIds: number[]) {
    const titleAnswers = await inquirer.prompt({
      type: 'input',
      name: 'title',
      message: __('enterTitle'),
      default: reviewFacade.titleRaw,
    });
    const newTitle = titleAnswers.title;
    const result = await this.updateReview(reviewFacade, projectId, { title: newTitle, ccUserIds });
    if (!result) {
      this.updateFailed();
      return;
    }
  }

  /**
   * 交互式更新描述
   * @param reviewFacade
   * @param projectId
   * @returns
   */
  private async updateDescriptionInteractive(reviewFacade: ReviewFacade, projectId: number, ccUserIds: number[]) {
    const descAnswers = await inquirer.prompt({
      type: 'editor',
      name: 'description',
      message: __('enterDescription'),
      default: reviewFacade.comparison?.descriptionRaw || reviewFacade.svnMergeRequest?.description,
    });
    const newDesc = descAnswers.description;
    const result = await this.updateReview(reviewFacade, projectId, { description: newDesc, ccUserIds });
    if (!result) {
      this.updateFailed();
      return;
    }
  }

  /**
   * 交互式更新评审人
   * @param targetProject
   * @param reviewFacade
   * @param reviewersFromConfig 已选择的评审人
   */
  private async updateNormalReviewers(
    targetProject: Project4Detail,
    reviewFacade: ReviewFacade,
    reviewersFromConfig: Reviewer[],
    ccUserIds: number[],
  ) {
    const defaultUserChoices = reviewersFromConfig.map((reviewer) => ({
      name: reviewer.user.username,
      value: `${reviewer.user.id}`,
    }));
    const defaultValue = reviewersFromConfig.map((reviewer) => `${reviewer.user.id}`);
    const reviewerAnswers = await inquirer.prompt([
      {
        type: 'checkbox-plus',
        name: 'reviewers',
        message: __('selectReviewers'),
        pageSize: 10,
        highlight: false,
        searchable: true,
        default: defaultValue,
        suffix: color.dim(__('selectTip')),
        source: async (answersSoFar: object, input: string) => {
          return this.apiService.getUserChoices(input, targetProject, defaultUserChoices);
        },
      },
    ]);
    const reviewerIds = reviewerAnswers.reviewers.join(SEPARATOR);
    await this.updateReview(reviewFacade, targetProject.id, { reviewerIds, ccUserIds });
  }

  /**
   * 交互式更新必要评审人
   * @param targetProject
   * @param reviewFacade
   * @param necessaryReviewersFromConfig 已选择的必要评审人
   */
  private async updateNecessaryReviewers(
    targetProject: Project4Detail,
    reviewFacade: ReviewFacade,
    necessaryReviewersFromConfig: Reviewer[],
  ) {
    const defaultUserChoices = necessaryReviewersFromConfig.map((reviewer) => ({
      name: reviewer.user.username,
      value: `${reviewer.user.id}`,
    }));
    const defaultValue = necessaryReviewersFromConfig.map((reviewer) => `${reviewer.user.id}`);
    const reviewerAnswers = await inquirer.prompt([
      {
        type: 'checkbox-plus',
        name: 'necessaryReviewers',
        message: __('selectNecessaryReviewers'),
        pageSize: 10,
        highlight: false,
        searchable: true,
        default: defaultValue,
        suffix: color.dim(__('selectTip')),
        source: async (answersSoFar: object, input: string) => {
          return this.apiService.getUserChoices(input, targetProject, defaultUserChoices);
        },
      },
    ]);
    const necessaryReviewerIds = reviewerAnswers.necessaryReviewers.join(SEPARATOR);
    await this.updateReview(reviewFacade, targetProject.id, { necessaryReviewerIds });
  }

  /**
   * 交互式更新抄送人
   * @param targetProject
   * @param reviewFacade
   * @param selectedCcUsers 已选择的抄送人
   */
  private async updateCcUsers(targetProject: Project4Detail, reviewFacade: ReviewFacade, selectedCcUsers: User[]) {
    const defaultUserChoices = selectedCcUsers.map((user) => ({
      name: user.username,
      value: `${user.id}`,
    }));
    const defaultValue = selectedCcUsers.map((reviewer) => `${reviewer.id}`);
    const reviewerAnswers = await inquirer.prompt([
      {
        type: 'checkbox-plus',
        name: 'ccUsers',
        message: __('selectCcUsers'),
        pageSize: 10,
        highlight: false,
        searchable: true,
        default: defaultValue,
        suffix: color.dim(__('selectTip')),
        source: async (answersSoFar: object, input: string) => {
          return this.apiService.getUserChoices(input, targetProject, defaultUserChoices);
        },
      },
    ]);
    const ccUserIds = reviewerAnswers.ccUsers;
    await this.updateReview(reviewFacade, targetProject.id, { ccUserIds });
  }

  /**
   * 交互式更新代码评审
   * @param reviewFacade
   * @param targetProject
   */
  private async updateReviewInteractive(reviewFacade: ReviewFacade, targetProject: Project4Detail) {
    const { iid } = reviewFacade;
    const { id } = targetProject;
    const answersType = await this.selectUpdateType();
    const ccUsers = await this.apiService.getReviewCCUsers(id, iid);
    const ccUserIds = ccUsers.map((user) => user.id);
    switch (answersType) {
      case InteractiveSelectType.TITLE: {
        // 交互更新标题
        await this.updateTitleInteractive(reviewFacade, id, ccUserIds);
        break;
      }
      case InteractiveSelectType.DESCRIPTION: {
        // 交互式更新描述
        await this.updateDescriptionInteractive(reviewFacade, id, ccUserIds);
        break;
      }
      case InteractiveSelectType.REVIEWER: {
        // case InteractiveSelectType.NECESSARY_REVIEWER: {
        // 获取已选择的评审人
        const { normalReviewers } = await this.apiService.getReviewConfig(id, iid);
        if (answersType === InteractiveSelectType.REVIEWER) {
          // 交互更新评审人
          await this.updateNormalReviewers(targetProject, reviewFacade, normalReviewers, ccUserIds);
        }
        // svn 没有必要评审人
        // if (answersType === InteractiveSelectType.NECESSARY_REVIEWER) {
        //   // 交互更新必要评审人
        //   await this.updateNecessaryReviewers(targetProject, reviewFacade, necessaryReviewers);
        // }
        break;
      }
      case InteractiveSelectType.CC_USERS: {
        // 交互更新抄送人
        await this.updateCcUsers(targetProject, reviewFacade, ccUsers);
        break;
      }
    }
  }

  private async selectUpdateType() {
    const answers = await inquirer.prompt({
      type: 'list',
      name: 'type',
      message: __('selectEditType'),
      choices: [
        {
          name: __('editTitle'),
          value: InteractiveSelectType.TITLE,
        },
        {
          name: __('editDescription'),
          value: InteractiveSelectType.DESCRIPTION,
        },
        {
          name: __('editReviewers'),
          value: InteractiveSelectType.REVIEWER,
        },
        // {
        //   name: __('editNecessaryReviewers'),
        //   value: InteractiveSelectType.NECESSARY_REVIEWER,
        // },
        {
          name: __('editCcUsers'),
          value: InteractiveSelectType.CC_USERS,
        },
      ],
    });
    return answers.type;
  }

  /** 校验评审状态 */
  private isCrOpen(state: ReviewState) {
    return state === ReviewState.APPROVING || state === ReviewState.REOPENED;
  }

  private updateFailed() {
    console.log(color.error(__('updateCrError')));
    this.exit(0);
    return;
  }

  /**
   * 校验用户名列表中的用户是否项目成员
   * @param usernames 用户名数组
   * @returns 返回合法用户和非法用户名
   */
  private async validateProjectUserNames(
    project: Project4Detail,
    usernames: string[],
    invalidMessage = 'invalidUsernamesIgnored',
  ) {
    const validUsers: AutocompleteUser[] = [];
    const invalidUsernames: string[] = [];

    for (const username of usernames) {
      const user = await this.apiService.getProjectMember(project, username);
      if (user) {
        validUsers.push(user);
      } else {
        invalidUsernames.push(username);
      }
    }
    if (invalidUsernames.length) {
      console.log(color.error(__(invalidMessage, { users: invalidUsernames.join(SEPARATOR) })));
    }
    return validUsers;
  }
}
