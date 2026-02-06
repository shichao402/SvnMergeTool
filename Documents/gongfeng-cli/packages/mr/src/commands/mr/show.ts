import BaseCommand from '../../base';
import { Flags, Args } from '@oclif/core';
import { getUrlWithAdTag, color, getCurrentRemote, git, vars } from '@tencent/gongfeng-cli-base';
import ApiService from '../../api-service';
import {
  initializeReviewersType,
  isNumeric,
  normalizeCertifiedReviewers,
  refreshSelectedIdCache,
  tryPromptDoubleRoleReviewers,
  getCommitCheckerOverviewStatus,
  checkIfBlockingChecker,
} from '../../util';
import { CertifiedReviewer, MergeRequestState, MergeRequest4Detail, CommitCheck } from '../../type';
import * as ora from 'ora';
import * as open from 'open';
import {
  CertifiedReviewerType,
  CommitCheckState,
  Review,
  ReviewState,
} from '@tencent/gongfeng-cli-base/dist/gong-feng';

/**
 * 合并请求详情命令
 */
export default class Show extends BaseCommand {
  static summary = '查看单个合并请求';
  static description = `
显示单个合并请求的标题、描述、状态、评审人等信息
如果不指定合并请求的 iid 或源分支，默认显示属于当前分支且正在处理中的合并请求`;
  static examples = ['gf mr show 42', 'gf mr show dev'];
  static usage = 'mr show <iidOrBranch> [flags]';

  static args = {
    iidOrBranch: Args.string({
      required: false,
      description: '合并请求 iid 或者源分支名称',
    }),
  };

  static flags = {
    web: Flags.boolean({
      char: 'w',
      description: '打开浏览器查看合并请求',
      required: false,
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
    const { args, flags } = await this.parse(Show);
    const currentPath = process.cwd();

    let targetProjectPath = '';
    if (flags.repo) {
      targetProjectPath = flags.repo.trim();
    } else {
      const currentRemote = await getCurrentRemote(currentPath);
      if (!currentRemote) {
        console.log(color.error(__('currentRemoteNotFound')));
        this.exit(0);
        return;
      }
      targetProjectPath = (await git.projectPathFromRemote(currentPath, currentRemote.name)) ?? '';
    }

    const fetchProjectDetailSpinner = ora().start(__('fetchProjectDetail'));
    const targetProject = await this.apiService.getProjectDetail(targetProjectPath);
    fetchProjectDetailSpinner.stop();
    if (!targetProject) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    // 由于后续还有异步请求，同属获取 MR 详细信息，因此等待最终输出前再 stop
    const fetchMergeRequestDetailSpinner = ora().start(__('fetchMergeRequestDetail'));
    const projectId = targetProject.id;
    const branch = args.iidOrBranch || (await git.getCurrentBranch(currentPath));
    if (!branch) {
      console.log(color.error(__('targetBranchNotFound')));
      return;
    }
    const mergeRequest4Detail = await this.apiService.getMergeRequest4DetailByIidOrBranch(projectId, branch);
    if (!mergeRequest4Detail) {
      fetchMergeRequestDetailSpinner.stop();
      if (isNumeric(branch)) {
        console.log(color.error(__('mergeRequestNotFound', { iidOrBranch: branch })));
      } else {
        console.log(color.error(__('mergeRequestNotFoundForBranch', { branch })));
      }
      this.exit(0);
      return;
    }

    const { mergeRequest } = mergeRequest4Detail;
    const mergeRequestUrl = this.getMergeRequestUrl(targetProjectPath, mergeRequest.iid);
    // 在浏览器中打开
    if (flags.web) {
      fetchMergeRequestDetailSpinner.stop();
      console.log(__('openUrl', { url: mergeRequestUrl }));
      await open(mergeRequestUrl);
      return;
    }
    // 输出 MR 详情
    const formattedMergeRequest = await this.formatMergeRequest(mergeRequest4Detail);
    fetchMergeRequestDetailSpinner.stop();
    console.log(formattedMergeRequest);
  }

  async formatMergeRequest(mergeRequest4Detail: MergeRequest4Detail) {
    const sections: string[] = [];
    const { mergeRequest, sourceProject, targetProject, review, commitChecks, labels, milestone } = mergeRequest4Detail;

    // 源分支 -> 目标分支
    const branchInfo =
      mergeRequest.sourceProjectId !== mergeRequest.targetProjectId
        ? `${sourceProject.fullPath} : ${mergeRequest.sourceBranch} -> ${mergeRequest.targetBranch}`
        : `${mergeRequest.sourceBranch} -> ${mergeRequest.targetBranch}`;
    const headSection = [
      `${this.getColoredState(mergeRequest.state)}•[!${mergeRequest.iid}] ${mergeRequest.titleRaw}`,
      branchInfo,
    ].join('\n');

    // 描述
    const descriptionSection = mergeRequest.descriptionRaw?.trim();

    // 作者，评审人，tapd等
    const infosSectionList = [];
    // 作者
    infosSectionList.push(__('author', { username: mergeRequest.author.username }));
    // 提交检查
    infosSectionList.push(...this.getCommitChecksInfo(commitChecks));
    // 负责人
    mergeRequest.assignee && infosSectionList.push(__('assignee', { username: mergeRequest.assignee.username }));
    // 标签
    if (labels?.length) {
      const labelStr = labels.map((label) => label.title).join(', ');
      infosSectionList.push(`${__('labels')}${labelStr}`);
    }
    // milestone
    if (milestone) {
      infosSectionList.push(__('milestone', { milestone: milestone.title }));
    }
    // 评审状态
    if (review.state !== ReviewState.EMPTY) {
      const reviewersDetailList = await this.getReviewersDetailList(targetProject.id, review);
      infosSectionList.push(...reviewersDetailList);
    }
    // tapd
    const tapdInfos = await this.getTapdsInfo(targetProject.id, review.iid);
    tapdInfos && infosSectionList.push(tapdInfos);
    // CC
    const CCInfos = await this.getCCInfo(targetProject.id, mergeRequest.iid);
    CCInfos && infosSectionList.push(CCInfos);
    const infosSection = infosSectionList.join('\n');
    const mergeRequestUrl = this.getMergeRequestUrl(targetProject.fullPath, mergeRequest.iid);
    const showUrlSection = color.gray(__('viewMergeRequestByUrl', { url: mergeRequestUrl }));

    // 拼接 MR 详细信息
    sections.push(headSection);
    descriptionSection && sections.push(descriptionSection);
    sections.push(infosSection);
    sections.push(showUrlSection);

    // 输入 MR 详细信息
    return sections.join('\n\n\n');
  }

  async getTapdsInfo(projectId: number, reviewIid: number) {
    const tapds = await this.apiService.getTapds(projectId, reviewIid);
    if (!tapds?.length) {
      return '';
    }
    const tapdsStr = tapds.map((tapd) => `    【${__(tapd.tapdType)}】: ${tapd.name}`);
    return `${__('tapd')}${tapdsStr}`;
  }

  async getCCInfo(projectId: number, mrIid: number) {
    const users = await this.apiService.getCC(projectId, mrIid);
    if (users?.length) {
      const usernames: string[] = [];
      users.forEach((user) => {
        usernames.push(user.username);
      });
      return __('carbonCopy', { usernames: usernames.join(',') });
    }
  }

  async getReviewersDetailList(projectId: number, review: Review) {
    const reviewersDetailList = [];
    if (review.state !== ReviewState.EMPTY) {
      reviewersDetailList.push(`${__('reviewState')}${__(review.state)}`);
    }
    const reviewers = await this.apiService.getReviewers(projectId, review.iid);
    if (!reviewers) {
      return reviewersDetailList;
    }

    const { necessaryReviewers: originNecessary, normalReviewers: originNormal, invalidUsers } = reviewers;
    let selectedIds: number[] = [];
    const { ordinary, necessary } = tryPromptDoubleRoleReviewers({
      ordinary: originNormal,
      necessary: originNecessary,
    });
    const invalidUserIds = new Set(invalidUsers.map((user) => user.id));

    const reviewerList = normalizeCertifiedReviewers(ordinary ?? [], invalidUserIds);
    const normalizedList = reviewerList.filter((reviewer) => !selectedIds.includes(reviewer.user.id));
    selectedIds = refreshSelectedIdCache(selectedIds, normalizedList);
    initializeReviewersType(reviewerList, CertifiedReviewerType.SUGGESTION);
    const selectedOrdinary = normalizedList;

    const necessaryList = normalizeCertifiedReviewers(necessary ?? [], invalidUserIds);
    const necessaryNormalizedList = necessaryList.filter((reviewer) => !selectedIds.includes(reviewer.user.id));
    selectedIds = refreshSelectedIdCache(selectedIds, necessaryNormalizedList);
    initializeReviewersType(necessaryList, CertifiedReviewerType.NECESSARY);
    const selectedNecessary = necessaryNormalizedList;

    if (!selectedNecessary?.length && !selectedOrdinary?.length) {
      return reviewersDetailList;
    }

    const necessaryStr = this.joinReviewers(selectedNecessary, true);
    const ordinaryStr = this.joinReviewers(selectedOrdinary);
    const reviewerStr = `${__('reviewers')}${necessaryStr}${ordinaryStr}`;
    reviewersDetailList.push(reviewerStr.slice(0, -1));
    return reviewersDetailList;
  }

  joinReviewers(reviewers: CertifiedReviewer[], necessary = false) {
    let reviewerStr = '';
    if (reviewers?.length) {
      reviewers.forEach((r) => {
        reviewerStr += `${r.user.username}${necessary ? '[V]' : ''}`;
        if (r.badges?.length) {
          r.badges.forEach((badge) => {
            reviewerStr += ` [${badge.name}-${badge.shortLanguage}]`;
          });
        }
        if (r.state) {
          reviewerStr += `(${__(r.state)}), `;
        }
      });
    }
    return reviewerStr;
  }

  getColoredState(state: MergeRequestState) {
    switch (state) {
      case MergeRequestState.CLOSED:
      case MergeRequestState.LOCKED: {
        return color.error(__(state));
      }
      case MergeRequestState.OPENED:
      case MergeRequestState.REOPENED: {
        return color.success(__(state));
      }
      case MergeRequestState.MERGED: {
        return color.info(__(state));
      }
      default: {
        return __(state);
      }
    }
  }

  getCommitChecksInfo(commitChecks: CommitCheck[]) {
    if (!commitChecks?.length) {
      return [];
    }
    const failedCheckSize = commitChecks.filter((c) => c.state === CommitCheckState.FAILURE)?.length ?? 0;
    const pendingCheckSize = commitChecks.filter((c) => c.state === CommitCheckState.PENDING)?.length ?? 0;
    const succeededCheckSize = commitChecks.filter((c) => c.state === CommitCheckState.SUCCESS)?.length ?? 0;
    const totalCommitCheckState = getCommitCheckerOverviewStatus(commitChecks);
    const checkInfos = `${__('checks')} ${color.bold(
      totalCommitCheckState,
    )} (${failedCheckSize} failed, ${pendingCheckSize} pending, ${succeededCheckSize} succeeded)`;
    const blockingChecks = commitChecks?.filter(checkIfBlockingChecker);
    if (blockingChecks.length === 0) {
      return [checkInfos];
    }
    const blockingCheckInfos = blockingChecks.map((blockCommitCheck) => `- ${blockCommitCheck.description}`).join('\n');
    return [checkInfos, blockingCheckInfos];
  }

  getMergeRequestUrl(targetProjectPath: string, mergeRequestIid: number) {
    return getUrlWithAdTag(`https://${vars.host()}/${targetProjectPath}/merge_requests/${mergeRequestIid}`);
  }
}
