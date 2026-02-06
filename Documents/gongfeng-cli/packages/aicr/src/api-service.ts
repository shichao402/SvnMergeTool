import { AxiosInstance } from 'axios';
import { color, normalizeProjectPath, Project4Detail, Models } from '@tencent/gongfeng-cli-base';
import Debug from 'debug';
import { AIReviewResult, PatchFile } from './type';
import { formatTimeToISO } from './util';

const debug = Debug('gongfeng-mr:api-service');

export default class ApiService {
  api!: AxiosInstance;
  copilotApi!: AxiosInstance;
  constructor(api: AxiosInstance, copilotApi: AxiosInstance) {
    this.api = api;
    this.copilotApi = copilotApi;
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
    // 第一次尝试直接获取项目详情
    try {
      const { data } = await this.api.get(`/projects/${normalizeProjectPath(projectPath)}`);
      return data;
    } catch (e: any) {
      debug(`getProjectDetail error: ${e.message}`);
    }
    // 修改 projectPath，在项目组后加 _svn,兼容老svn项目
    const parts = projectPath.split('/');
    if (parts.length >= 2) {
      parts[parts.length - 2] += '_svn';
      const modifiedPath = parts.join('/');
      try {
        const { data } = await this.api.get(`/projects/${normalizeProjectPath(modifiedPath)}`);
        return data;
      } catch (e: any) {
        debug(`getProjectDetail retry error: ${e.message}`);
      }
    }
    return null;
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

  async createAIReview(
    projectId: number,
    title: string,
    files: PatchFile[],
    options: {
      begintime?: Date | string;
      endtime?: Date | string;
      timeBack?: string;
      ref?: string;
      fromversion?: string;
      stopversion?: string;
      cc?: string;
      author?: string;
      path?: string;
      selected?: string[];
      exclude?: string[];
    } = {},
  ): Promise<AIReviewResult | null> {
    const url = '/cr/cli';
    // 创建新的 payload 对象，处理时间格式
    const payload: any = {
      projectId,
      title,
      files,
    };

    // 处理 begintime
    if (options.begintime) {
      payload.begintime = formatTimeToISO(options.begintime);
    }

    // 处理 endtime
    if (options.endtime) {
      payload.endtime = formatTimeToISO(options.endtime);
    }

    // 复制其他选项
    Object.keys(options).forEach((key) => {
      if (key !== 'begintime' && key !== 'endtime') {
        payload[key] = (options as any)[key];
      }
    });

    debug(`payload: ${JSON.stringify(payload)}`);
    try {
      const { data } = await this.copilotApi.post(url, payload);
      return data;
    } catch (e: any) {
      debug(`create AI review error: ${e.message}`);
      // 提取服务端的详细错误信息
      if (e.response) {
        console.log('\n');
        const responseData = e.response.data;
        if (responseData) {
          if (responseData.message) {
            console.log(color.error(`error message: ${responseData.message}`));
          }
          if (responseData.code) {
            console.log(color.error(`Error code: ${responseData.code}`));
          }
        }
      } else if (e.request) {
        // 请求已发出但没有收到响应
        console.log(color.error('No response received from server'));
      } else {
        // 其他错误
        console.log(color.error(`Request setup error: ${e.message}`));
      }
      console.log('\n');
      return null;
    }
  }
}
