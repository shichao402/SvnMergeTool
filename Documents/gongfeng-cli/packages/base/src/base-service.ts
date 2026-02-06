import { AxiosInstance } from 'axios';
import { Project4Detail, User, normalizeProjectPath, AutocompleteUser, AutocompleteUserOptions } from './gong-feng';
import * as qs from 'qs';
import Debug from 'debug';
import { UserSession } from './models';

const debug = Debug('gongfeng-release:api-service');

export default class BaseApiService {
  api!: AxiosInstance;
  constructor(api: AxiosInstance) {
    this.api = api;
  }

  async getProjectDetail(projectPath: string): Promise<Project4Detail | null> {
    try {
      const { data } = await this.api.get(`/projects/${normalizeProjectPath(projectPath)}`);
      return data;
    } catch (e: any) {
      debug(`getProjectDetail error: ${e.message}`);
    }
    return null;
  }

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
   * 获取当前用户在 项目/项目组 下的权限信息
   * @param idOrPath 项目/项目组 id 或者 path
   * @param headersWithToken 用于使用 token 登录之后请求用户信息
   */
  async getCurrentUser(idOrPath?: string, headersWithToken?: any): Promise<UserSession> {
    const { data } = await this.api.get('/users/session/route', {
      params: {
        path: idOrPath,
      },
      headers: headersWithToken,
    });
    return data;
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
}
