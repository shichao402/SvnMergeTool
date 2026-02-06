import { AxiosInstance } from 'axios';
import { normalizeProjectPath, Project4Detail, Models } from '@tencent/gongfeng-cli-base';
import Debug from 'debug';
import { BlobContentForm } from './type';

const debug = Debug('gongfeng-mr:api-service');

export default class ApiService {
  api!: AxiosInstance;
  constructor(api: AxiosInstance) {
    this.api = api;
  }

  async getCurrentUser(idOrPath: string): Promise<Models.UserSession> {
    const { data } = await this.api.get('/users/session/route', {
      params: {
        path: idOrPath,
      },
    });
    return data;
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

  /**
   * 获取文件内容
   * @param projectPath 项目路径
   * @param blobContentForm
   */
  async getProjectBlobContent(projectPath: string, blobContentForm: BlobContentForm) {
    const url = `/projects/${normalizeProjectPath(projectPath)}/repository/blob/content`;
    const { data } = await this.api.get<string>(url, { params: blobContentForm });
    return data;
  }
}
