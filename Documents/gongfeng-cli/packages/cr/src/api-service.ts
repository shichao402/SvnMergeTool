import { AxiosInstance } from 'axios';
import Debug from 'debug';
import {
  BaseApiService,
  Project4Detail,
  ApiUserStateScope,
  AutocompleteUser,
  AutocompleteUserScope,
  UserSelectChoice,
  logger,
  User,
  Label,
} from '@tencent/gongfeng-cli-base';

import { isPublic } from './util';
import {
  ReviewConfigMixIn,
  ReviewEventEnum,
  ReviewFacade,
  ReviewForm,
  ReviewSearchForm,
  ReviewWrapperDocFacadeMixIn,
  SvnPresetReviewConfigFacade,
  SvnReviewCreatedForm,
  TapdModel,
  TapdTicketForm,
} from './type';
import * as qs from 'qs';

const debug = Debug('gongfeng-cr:api-service');
export default class ApiService extends BaseApiService {
  api!: AxiosInstance;

  async getUserChoices(search: string, targetProject: Project4Detail, defaultChoices: UserSelectChoice[]) {
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
      users.forEach((user: AutocompleteUser) => {
        choices.push({
          name: user.username,
          value: `${user.id}`,
        });
      });
    }
    defaultChoices.forEach((choice) => {
      if (!choices.find((c) => c.name === choice.name)) {
        choices.push(choice);
      }
    });
    return choices;
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

  async getTapdRelModel(urlOrKeywords: string) {
    const url = '/users/tapd/tapd_rel_model';
    const { data } = await this.api.get<TapdModel>(url, {
      params: {
        url_or_keywords: urlOrKeywords,
      },
    });
    return data;
  }

  async getSvnProject(svnUrl: string) {
    const url = '/svn/project/cli/analyze_project';
    try {
      const { data } = await this.api.get<Project4Detail>(url, {
        params: {
          fullPath: svnUrl,
        },
      });
      return data;
    } catch (e: any) {
      debug(`get svn project error: ${e.message}`);
      return null;
    }
  }

  async getPresetConfig(projectId: number, filePaths?: string[]) {
    const url = `/svn/projects/${projectId}/path_rules/code_review/preset_config`;
    const { data } = await this.api.post<SvnPresetReviewConfigFacade>(
      url,
      qs.stringify({ filePaths }, { arrayFormat: 'repeat' }),
    );
    return data;
  }

  async createReview(
    projectId: number,
    diffContent: string,
    diffOnlyFileName = false,
    targetPath: string,
    title: string,
    description?: string,
    reviewerIds?: string,
    tapdTickets?: TapdTicketForm[],
    ccUserIds?: number[],
    author?: string,
  ) {
    const url = `/svn/projects/${projectId}/merge_requests`;
    const { data } = await this.api.post(
      url,
      qs.stringify(
        {
          targetProjectId: projectId,
          sourceProjectId: projectId,
          diffContent,
          diffOnlyFileName,
          targetPath,
          sourcePath: targetPath,
          title,
          description,
          reviewerIds,
          tapdTickets,
          ccUserIds,
          author,
        },
        { allowDots: true },
      ),
      {
        timeout: 125 * 1000,
      },
    );
    return data;
  }

  async createPatchSet(
    projectId: number,
    iid: number,
    diffContent: string,
    diffOnlyFileName = false,
    targetPath: string,
    description?: string,
    author?: string,
  ) {
    const url = `/svn/projects/${projectId}/reviews/${iid}/patchsets`;
    const { data } = await this.api.post(
      url,
      qs.stringify({
        targetProjectId: projectId,
        sourceProjectId: projectId,
        diffContent,
        diffOnlyFileName,
        targetPath,
        description,
        author,
      }),
      {
        timeout: 125 * 1000,
      },
    );
    return data;
  }

  async getReviewFacade(projectId: number, reviewIid: number) {
    const url = `/projects/${projectId}/reviews/${reviewIid}`;
    try {
      const { data } = await this.api.get<ReviewFacade>(url);
      return data;
    } catch (e: any) {
      debug(`getReviewFacade error: ${e.message}`);
      logger.error(e.message);
      return null;
    }
  }

  async patchReviewSummary(projectId: number, reviewIid: number, reviewForm: ReviewForm) {
    const url = `/projects/${projectId}/reviews/${reviewIid}/summary?${qs.stringify(reviewForm)}`;
    try {
      await this.api.patch(url);
      return true;
    } catch (e: any) {
      debug(`patchReviewerSummary error: ${e.message}`);
      logger.error(e.message);
      return false;
    }
  }

  addComment(projectId: number, reviewIid: number, comment: string) {
    return this.patchReviewSummary(projectId, reviewIid, { reviewerEvent: ReviewEventEnum.COMMENT, summary: comment });
  }

  closeReview(projectId: number, reviewIid: number) {
    return this.patchReviewSummary(projectId, reviewIid, { reviewerEvent: ReviewEventEnum.CLOSE });
  }

  reopenReview(projectId: number, reviewIid: number) {
    return this.patchReviewSummary(projectId, reviewIid, { reviewerEvent: ReviewEventEnum.REOPEN });
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

  async searchReviews(projectIid: number, form: ReviewSearchForm) {
    const url = `/projects/${projectIid}/code_review?${qs.stringify(form, { arrayFormat: 'repeat' })}`;

    try {
      const res = await this.api.get<ReviewWrapperDocFacadeMixIn[]>(url);
      return res.data;
    } catch (e: any) {
      debug(`searchReviews error: ${e.message}`);
      logger.error(e.message);
      return null;
    }
  }

  async updateSvnReviewCodeInLocal(projectId: number, iid: number, form: Partial<SvnReviewCreatedForm>) {
    const url = `/svn/projects/${projectId}/merge_requests/${iid}`;
    try {
      await this.api.put(url, qs.stringify(form, { allowDots: true }));
      return true;
    } catch (e: any) {
      debug(`updateSvnReviewCodeInLocal error: ${e.message}`);
      logger.error(e.message);
      return false;
    }
  }

  async updateReview(projectId: number, iid: number, form: Partial<SvnReviewCreatedForm>) {
    const url = `/svn/projects/${projectId}/reviews/${iid}`;
    try {
      await this.api.put(url, qs.stringify(form, { allowDots: true }));
      return true;
    } catch (e: any) {
      debug(`updateReview error: ${e.message}`);
      logger.error(e.message);
      return false;
    }
  }

  async getReviewConfig(projectId: number, reviewIid: number) {
    const url = `/projects/${projectId}/reviews/${reviewIid}/config`;
    const { data } = await this.api.get<ReviewConfigMixIn>(url);
    return data;
  }

  async getReviewCCUsers(projectId: number, reviewIid: number) {
    const url = `/projects/${projectId}/reviews/${reviewIid}/cc/users`;
    const { data } = await this.api.get<User[]>(url);
    return data;
  }

  async getLabelByTitle(projectId: number, labelTitles: string[]) {
    const params = qs.stringify({ titles: labelTitles }, { arrayFormat: 'repeat' });
    const url = `/projects/${projectId}/labels/filter?${params}`;
    const { data } = await this.api.get<Label[]>(url);
    return data;
  }
}
