import { AxiosInstance } from 'axios';
import { Platform } from './type';
import { getFormatDate } from './utils';

export default class ApiService {
  api!: AxiosInstance;

  constructor(api: AxiosInstance) {
    this.api = api;
  }

  async getConfig(platform: Platform) {
    const { data } = await this.api.get('/config/get_config', {
      params: {
        platform,
      },
    });
    return data;
  }

  async updateError({ code = -1, message }: { code?: number; message: string }) {
    const { data } = await this.api.post('/log/error', {
      code,
      message,
      timeLocal: getFormatDate(new Date()),
    });
    return data;
  }
}
