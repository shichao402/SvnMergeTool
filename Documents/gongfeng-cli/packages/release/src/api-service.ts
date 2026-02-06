import { BaseApiService } from '@tencent/gongfeng-cli-base';
import * as qs from 'qs';
import Debug from 'debug';
import { TagReleaseFacade } from './type';

const debug = Debug('gongfeng-release:api-service');

export default class ApiService extends BaseApiService {
  /**
   * 搜索 release
   * @param projectId 项目 id
   * @param perPage 分页大小
   * @param authorId 作者 id
   * @param labels 标签
   */
  async searchReleases(
    projectId: number,
    perPage: number,
    authorId?: number,
    labels?: string[],
  ): Promise<TagReleaseFacade[]> {
    try {
      const params = qs.stringify(
        {
          authorId,
          labels,
          perPage,
        },
        { arrayFormat: 'repeat' },
      );
      const url = `/projects/${projectId}/releases?${params}`;
      const { data } = await this.api.get<TagReleaseFacade[]>(url);
      return data;
    } catch (e: any) {
      debug(`searchReleases error: ${e.message}`);
    }
    return [];
  }

  /**
   * 通过 tag 或者 release
   * @param projectId 项目 id
   * @param tagName tag 名称
   */
  async getReleaseByTagName(projectId: number, tagName: string) {
    try {
      const url = encodeURI(`/projects/${projectId}/releases/${tagName}`);
      const { data } = await this.api.get<TagReleaseFacade>(url);
      return data;
    } catch (e: any) {
      debug(`getReleaseByTagName error: ${e.message}`);
    }
    return null;
  }
}
