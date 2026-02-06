import { AxiosInstance } from 'axios';
import * as qs from 'qs';
import { normalizeProjectPath, Project4Detail, User } from '@tencent/gongfeng-cli-base';
import Debug from 'debug';
import { IssueFacade } from './type';

const debug = Debug('gongfeng-issue:api-service');

export default class ApiService {
  api!: AxiosInstance;
  constructor(api: AxiosInstance) {
    this.api = api;
  }

  /**
   * 获取项目详细信息
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
   * 搜索 issue
   * @param projectId 项目 id
   * @param assigneeId 分配人 id
   * @param authorId 作者 id
   * @param state 状态
   * @param labels 标签
   * @param perPage 分页大小
   */
  async searchIssues(
    projectId: number,
    assigneeId?: number,
    authorId?: number,
    state?: string,
    labels?: string,
    perPage?: number,
  ) {
    try {
      const url = `/projects/${projectId}/issues`;
      const { data } = await this.api.get<IssueFacade[]>(url, {
        params: {
          assigneeId,
          authorId,
          labels,
          state,
          perPage,
          sort: 'created_desc',
        },
      });
      return data;
    } catch (e: any) {
      debug(`searchIssues error: ${e.message}`);
      return new Array<IssueFacade>();
    }
  }

  /**
   * 获取 issue 详情
   * @param projectId 项目 id
   * @param iid issue iid
   */
  async getIssueDetailByIid(projectId: number, iid: number) {
    try {
      const url = `/projects/${projectId}/issues/${iid}`;
      const { data } = await this.api.get<IssueFacade>(url);
      return data;
    } catch (e: any) {
      debug(`getIssueDetailByIid error: ${e.message}`);
      return null;
    }
  }
}
