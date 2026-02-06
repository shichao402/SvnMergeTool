import { AxiosInstance, AxiosResponse } from 'axios';
import * as qs from 'qs';
import {
  normalizeProjectPath,
  Project4Detail,
  User,
  ProtectedBranch,
  logger,
  Models,
  ApiUserMixin,
  AutocompleteUser,
} from '@tencent/gongfeng-cli-base';
import Debug from 'debug';
import {
  MergeRequest4Detail,
  ApiCertifiedReviewer,
  TapdItem,
  MergeRequestFacade,
  ReadyMergeRequest,
  MergeRequestParams,
  MergeRequest,
  CertifiedReviewer,
  MergeRequestReviewers,
  AutocompleteUserOptions,
  ReviewEvent,
  UserSelectChoice,
  AutocompleteUserScope,
  ApiUserStateScope,
  MergeRequestState,
} from './type';
import {
  initializeReviewersType,
  isNumeric,
  isPublic,
  normalizeCertifiedReviewers,
  normalizeLegacyUsersAsReviewers,
  tryPromptDoubleRoleReviewers,
} from './util';
import * as _ from 'lodash';
import { Badge, CertifiedReviewerType } from '@tencent/gongfeng-cli-base/dist/gong-feng';

const debug = Debug('gongfeng-mr:api-service');

export default class ApiService {
  api!: AxiosInstance;
  constructor(api: AxiosInstance) {
    this.api = api;
  }

  /**
   * 获取当前用户在 项目/项目组 下的权限信息
   * @param idOrPath 项目/项目组 id 或者 path
   */
  async getCurrentUser(idOrPath: string): Promise<Models.UserSession> {
    const { data } = await this.api.get('/users/session/route', {
      params: {
        path: idOrPath,
      },
    });
    return data;
  }

  /**
   * 获取项目详情
   * @param projectPath 项目路径
   */
  async getProjectDetail(projectPath: string): Promise<Project4Detail | null> {
    try {
      const { data } = await this.api.get(`/projects/${normalizeProjectPath(projectPath)}`);
      return data;
    } catch (e: any) {
      debug(`getProjectDetail error: ${e.message}`);
    }
    return null;
  }

  /**
   * 更新合并请求
   * @param projectId 项目 id
   * @param iid 合并请求 iid
   * @param params 合并请求参数
   */
  async updateMergeRequest(projectId: number, iid: number, params: Partial<MergeRequestParams>) {
    try {
      const url = `/projects/${projectId}/merge_requests/${iid}`;
      await this.api.put(url, qs.stringify(params));
      return true;
    } catch (e) {
      logger.error('update merge request error', e);
    }
    return false;
  }

  /**
   * 批量保存普通评审人和必要评审人
   *
   * @notice
   * 接口会自动计算出需要移除和新增的评审人，前端无需区分
   *
   * @param projectId
   * @param reviewIid
   * @param ordinaryReviewerIds
   * @param necessaryReviewerIds
   *
   * @return {Promise<CertifiedReviewer[]>} 返回保存结果用户数据
   */
  async batchSubmitReviewers(
    projectId: number,
    reviewIid: number,
    ordinaryReviewerIds: number[] = [],
    necessaryReviewerIds: number[] = [],
  ) {
    const url = `/projects/${projectId}/reviews/${reviewIid}/reviewer/batch_update`;

    const formData = new URLSearchParams();
    if (ordinaryReviewerIds.length > 0) {
      formData.append('normalReviewerIds', ordinaryReviewerIds.join(','));
    }
    if (necessaryReviewerIds.length > 0) {
      formData.append('necessaryReviewerIds', necessaryReviewerIds.join(','));
    }

    const { data } = await this.api.post<any, AxiosResponse<CertifiedReviewer[]>>(url, formData);
    return data;
  }

  /**
   * 通过合并请求 iid 获取合并请求详情
   * @param projectId 项目 id
   * @param iid 合并请求 iid
   */
  async getMergeRequestByIid(projectId: number, iid: number): Promise<MergeRequest4Detail | null> {
    try {
      const { data } = await this.api.get(`/projects/${projectId}/merge_requests/${iid}`);
      return data;
    } catch (e: any) {
      debug(`getMergeRequestByIid error: ${e.message}`);
    }
    return null;
  }

  /**
   * 获取评审评审人
   * @param projectId 项目 id
   * @param reviewIid 评审 iid
   */
  async getReviewers(projectId: number, reviewIid: number) {
    try {
      const url = `/projects/${projectId}/reviews/${reviewIid}/config`;
      const { data } = await this.api.get<{
        necessaryReviewers: ApiCertifiedReviewer[];
        normalReviewers: ApiCertifiedReviewer[];
        validBadges: Badge[];
        author: ApiCertifiedReviewer;
        invalidUsers: ApiUserMixin[];
      }>(url);
      return data;
    } catch (e: any) {
      debug(`getReviewer error: ${e.message}`);
    }
    return null;
  }

  /**
   * 获取合并请求抄送人员
   * @param projectId 项目 id
   * @param mrIid 合并请求 iid
   */
  async getCC(projectId: number, mrIid: number): Promise<User[]> {
    try {
      const url = `/projects/${projectId}/cc/users?ccType=MergeRequest&iid=${mrIid}`;
      const { data } = await this.api.get(url);
      return data;
    } catch (e: any) {
      debug(`getReviewer error: ${e.message}`);
    }
    return [];
  }

  /**
   * 获取评审 tapd 工单
   * @param projectId 项目 id
   * @param reviewIid 评审 iid
   */
  async getTapds(projectId: number, reviewIid: number): Promise<TapdItem[]> {
    try {
      const url = `/projects/${projectId}/reviews/${reviewIid}/tapds`;
      const { data } = await this.api.get(url);
      return data;
    } catch (e: any) {
      debug(`getTapds error: ${e.message}`);
    }
    return [];
  }

  /**
   * 搜索用户
   * @param usernames 用户名
   */
  async searchUsers(usernames: string[]): Promise<User[]> {
    try {
      const url = '/users';
      const { data } = await this.api.post(url, qs.stringify({ usernames }, { arrayFormat: 'repeat' }));
      return data;
    } catch (e: any) {
      debug(`searchUsers error: ${e.message}`);
    }
    return [];
  }

  /**
   * 搜索合并请求
   * @param projectId 项目 id
   * @param assigneeId 分配人 id
   * @param reviewerId 评审人 id
   * @param authorId 作者 id
   * @param state 状态
   * @param branch 目标分支
   * @param labels 标签
   * @param perPage 分页大小
   * @param sourceBranch 源分支
   */
  async searchMergeRequests(
    projectId: number,
    assigneeId?: number,
    reviewerId?: number,
    authorId?: number,
    state?: string,
    branch?: string,
    labels?: string,
    perPage?: number,
    sourceBranch?: string,
  ): Promise<MergeRequestFacade[]> {
    try {
      const query = qs.stringify({
        assigneeId,
        reviewerId,
        authorId,
        state,
        branch,
        labels,
        perPage,
        sourceBranch,
        sort: 'created_desc',
      });
      const url = `/projects/${projectId}/merge_requests?${query}`;
      const { data } = await this.api.get(url);
      return data;
    } catch (e: any) {
      debug(`searchMergeRequests error: ${e.message}`);
    }
    return [];
  }

  /**
   * 根据源分支获取合并请求
   * @param projectId 项目 id
   * @param sourceBranch 源分支
   * @param state 状态
   */
  async searchLatestMergeRequestBySourceBranch(projectId: number, sourceBranch: string, state?: string) {
    return this.searchMergeRequests(
      projectId,
      undefined,
      undefined,
      undefined,
      state,
      undefined,
      undefined,
      1,
      sourceBranch,
    );
  }

  /**
   * 根据评审人搜索合并请求
   * @param projectId 项目id
   * @param reviewerId 评审人 id
   */
  async searchMergeRequestByReviewer(projectId: number, reviewerId: number) {
    return this.searchMergeRequests(projectId, undefined, reviewerId);
  }

  /**
   * 根据作者搜索合并请求
   * @param projectId 项目 id
   * @param authorId 作者 id
   */
  async searchMergeRequestByAuthor(projectId: number, authorId: number) {
    return this.searchMergeRequests(projectId, undefined, undefined, authorId);
  }

  /**
   * 搜索可以合入的合并请求
   * @param projectId 项目 id
   * @param userId 用户 id
   */
  async searchMergeRequestReadyToMerge(projectId: number, userId: number): Promise<ReadyMergeRequest[]> {
    const url = `/projects/${projectId}/code_review/?authorId=${userId}&reviewerId=${userId}&assigneeId=${userId}&type=web_ready_to_merge&order=readyToMergeAt`;
    try {
      const { data } = await this.api.get(url);
      return data;
    } catch (e: any) {
      debug(`searchMergeRequestReadyToMerge error: ${e.message}`);
    }
    return [];
  }

  /**
   * 创建合并请求
   * @param projectId 项目 id
   * @param params
   */
  async createMergeRequest(projectId: number, params: MergeRequestParams): Promise<MergeRequest> {
    const url = `/projects/${projectId}/merge_requests`;
    const { data } = await this.api.post(url, qs.stringify(params), {
      timeout: 125 * 1000,
    });
    return data;
  }

  /**
   * 关闭合并请求
   * @param projectId 项目 id
   * @param mrIid 合并请求 iid
   */
  async closeMergeRequest(projectId: number, mrIid: number): Promise<boolean> {
    const url = `/projects/${projectId}/merge_requests/${mrIid}/closed`;
    try {
      await this.api.put<void>(url);
      return true;
    } catch (e: any) {
      debug(`closeMergeRequest error: ${e.message}`);
      logger.error(e.message);
      return false;
    }
  }

  /**
   * 重新打开合并请求
   * @param projectId 项目 id
   * @param mrIid 合并请求 iid
   */
  async reopenMergeRequest(projectId: number, mrIid: number): Promise<boolean> {
    const url = `/projects/${projectId}/merge_requests/${mrIid}/reopen`;
    try {
      await this.api.put<void>(url);
      return true;
    } catch (e: any) {
      debug(`reopenMergeRequest error: ${e.message}`);
      logger.error(e.message);
      return false;
    }
  }

  /**
   * 评论合并请求
   * @param projectId 项目 id
   * @param reviewIid 评审 iid
   * @param summary 评论
   */
  async patchReviewerSummary(projectId: number, reviewIid: number, summary: string) {
    const url = `/projects/${projectId}/reviews/${reviewIid}/summary`;
    try {
      await this.api.patch<void>(url, qs.stringify({ summary, reviewerEvent: ReviewEvent.COMMENT }));
      return true;
    } catch (e: any) {
      debug(`patchReviewerSummary error: ${e.message}`);
      logger.error(e.message);
      return false;
    }
  }
  /**
   * 获取预设评审人
   */
  async getPresetReviewersConfig(
    projectId: number,
    params: {
      targetBranch: string;
      sourceBranch: string;
      sourceObjectId: string;
      targetObjectId: string;
      sourceProjectId?: number;
    },
  ) {
    const url = `/projects/${projectId}/repository/branches/${encodeURIComponent(
      params.targetBranch,
    )}/review/preset_reviewers`;
    const { data } = await this.api.get<{
      necessaryReviewers: ApiUserMixin[] | null;
      suggestionReviewers: ApiUserMixin[] | null;
      invalidNecessaryReviewers: ApiUserMixin[] | null;
      invalidSuggestionReviewers: ApiUserMixin[] | null;
      validBadges: Badge[];
    }>(url, {
      params: {
        sourceObjectId: params.sourceObjectId,
        targetObjectId: params.targetObjectId,
        sourceProjectId: params.sourceProjectId,
      },
    });
    return data;
  }

  /**
   * 获取分支的配置信息（非保护 / 保护分支）
   * NOTICE: 该接口返回的 Mixin 与分支规则或项目配置不同，如有缺失，需联系后端同学补全 Mixin 字段
   */
  async getBranchConfig(projectId: number, branchName: string): Promise<ProtectedBranch> {
    const url = `/projects/${projectId}/repository/branches/${encodeURIComponent(branchName)}/config`;
    const { data } = await this.api.get<ProtectedBranch>(url);
    return data;
  }

  /**
   * 获取推荐 OWNERS 评审人
   */
  async getPresetOwnersConfig(
    targetProjectId: number,
    params: {
      targetBranch: string;
      sourceBranch: string;
      sourceObjectId: string;
      targetObjectId: string;
      // 一般用于跨项目
      sourceProjectId?: number;
    },
  ) {
    const url = `/projects/${targetProjectId}/repository/branches/${encodeURIComponent(
      params.targetBranch,
    )}/review/preset_owners`;
    const { data } = await this.api.post<ApiUserMixin[]>(
      url,
      qs.stringify({
        sourceObjectId: params.sourceObjectId,
        targetObjectId: params.targetObjectId,
        sourceProjectId: params.sourceProjectId,
      }),
    );
    return data;
  }

  /**
   * 获取默认评审人
   * @param targetProjectId 目标项目 id
   * @param targetBranch 目标分支
   * @param sourceBranch 源分支
   * @param sourceObjectId 源提交点
   * @param targetObjectId 目标提交点
   * @param sourceProjectId 源项目 id
   */
  async getDefaultReviewers(
    targetProjectId: number,
    targetBranch: string,
    sourceBranch: string,
    sourceObjectId: string,
    targetObjectId: string,
    sourceProjectId?: number,
  ): Promise<MergeRequestReviewers> {
    const {
      necessaryReviewers: originNecessary,
      suggestionReviewers: originOrdinary,
      invalidNecessaryReviewers,
      invalidSuggestionReviewers,
    } = await this.getPresetReviewersConfig(targetProjectId, {
      targetBranch,
      sourceBranch,
      sourceObjectId,
      targetObjectId,
    });

    let extraPresetOwners: ApiUserMixin[] = [];
    const protectBranch = await this.getBranchConfig(targetProjectId, targetBranch);
    if (protectBranch.ownersReviewEnabled) {
      const isCrossProject = targetProjectId !== sourceProjectId;
      extraPresetOwners = await this.getPresetOwnersConfig(targetProjectId, {
        targetBranch,
        sourceBranch,
        targetObjectId,
        sourceObjectId,
        sourceProjectId: isCrossProject ? sourceProjectId : undefined,
      });
    }

    const { ordinary, necessary } = tryPromptDoubleRoleReviewers({
      ordinary: normalizeLegacyUsersAsReviewers([...(originOrdinary ?? []), ...extraPresetOwners]),
      necessary: normalizeLegacyUsersAsReviewers(originNecessary),
    });

    const ordinaryReviewers = normalizeCertifiedReviewers(ordinary ?? []);
    initializeReviewersType(ordinaryReviewers, CertifiedReviewerType.SUGGESTION);

    const necessaryReviewers = normalizeCertifiedReviewers(necessary ?? []);
    initializeReviewersType(necessaryReviewers, CertifiedReviewerType.NECESSARY);

    const legacyNecessary = normalizeLegacyUsersAsReviewers(invalidNecessaryReviewers);
    const legacyOrdinary = normalizeLegacyUsersAsReviewers(invalidSuggestionReviewers);
    const removedReviewers = _.unionWith(
      [],
      legacyNecessary ?? [],
      legacyOrdinary ?? [],
      (a: CertifiedReviewer, b: CertifiedReviewer) => a.user.id === b.user.id,
    );

    return {
      reviewers: ordinaryReviewers,
      necessaryReviewers,
      removedReviewers,
    };
  }

  async filterUsers(options: AutocompleteUserOptions) {
    const url = '/autocomplete_sources/newly/users';
    const { data } = await this.api.get<AutocompleteUser[]>(url, {
      params: {
        ...options,
      },
    });
    return data;
  }

  /**
   * 获取项目成员
   * @param project 项目
   * @param username 用户名
   */
  async getProjectMember(project: Project4Detail, username: string): Promise<AutocompleteUser | null> {
    const isPublicProject = isPublic(project.visibilityLevel);
    const scope = isPublicProject ? AutocompleteUserScope.GLOBAL : AutocompleteUserScope.PROJECT;
    const users = await this.filterUsers({
      search: username,
      scope,
      scopeId: project.id,
      includeCurrentUser: false,
      perPage: 1,
      fullMatch: true,
      projectPriority: true,
      userState: ApiUserStateScope.ACTIVE,
    });
    if (users?.length) {
      return users[0];
    }
    return null;
  }

  async getUserChoices(
    search: string,
    targetProject: Project4Detail,
    config: ProtectedBranch,
    defaultChoices: UserSelectChoice[],
    currentUser?: string,
  ) {
    const isPublicProject = isPublic(targetProject.visibilityLevel);
    const scope = isPublicProject ? AutocompleteUserScope.GLOBAL : AutocompleteUserScope.PROJECT;
    const users = await this.filterUsers({
      search: search || '',
      scope,
      scopeId: targetProject.id,
      includeCurrentUser: false,
      perPage: 5,
      projectPriority: true,
      userState: ApiUserStateScope.ACTIVE,
    });
    const choices: UserSelectChoice[] = [];
    if (users?.length) {
      users.forEach((user) => {
        if (!config.canApproveByCreator && user.username === currentUser) {
          choices.push({
            name: user.username,
            value: `${user.id}`,
            disabled: true,
          });
        } else {
          choices.push({
            name: user.username,
            value: `${user.id}`,
          });
        }
      });
    }
    defaultChoices.forEach((choice) => {
      if (!choices.find((c) => c.name === choice.name)) {
        choices.push(choice);
      }
    });
    return choices;
  }

  async getMergeRequest4DetailByIidOrBranch(
    projectId: number,
    iidOrBranch: string,
    state?: MergeRequestState,
  ): Promise<MergeRequest4Detail | null> {
    // 优先当做数字处理
    if (isNumeric(iidOrBranch)) {
      const iid = parseInt(iidOrBranch, 10);
      const mergeRequest4Detail = await this.getMergeRequestByIid(projectId, iid);
      // 如果通过 iid 获取到 mergeRequest4Detail 则返回，否则当做分支名再进行搜索
      if (mergeRequest4Detail) {
        return mergeRequest4Detail;
      }
    }
    // 如果参数不为 iid 则搜索源分支为 branch 的 mr，并取第一个mr
    const mergeRequests: MergeRequestFacade[] = await this.searchLatestMergeRequestBySourceBranch(
      projectId,
      iidOrBranch,
      state,
    );
    if (!mergeRequests.length) {
      return null;
    }
    const [mergeRequestFacade] = mergeRequests;
    return await this.getMergeRequestByIid(projectId, mergeRequestFacade.mergeRequest.iid);
  }

  /**
   * 获取已经创建的合并情趣
   * @param targetProjectId 目标项目 id
   * @param sourceProjectId 源项目 id
   * @param targetBranch 目标分支
   * @param sourceBranch 源分支
   */
  async getSimilarMergeRequests(
    targetProjectId: number,
    sourceProjectId: number,
    targetBranch: string,
    sourceBranch: string,
  ) {
    try {
      const url = `/projects/${targetProjectId}/merge_requests/similar`;
      const { data } = await this.api.get<MergeRequest[]>(url, {
        params: { targetProjectId, sourceProjectId, sourceBranch, targetBranch },
      });
      return data;
    } catch (e: any) {
      debug(`getSimilarMergeRequests error: ${e.message}`);
      return [] as MergeRequest[];
    }
  }
}
