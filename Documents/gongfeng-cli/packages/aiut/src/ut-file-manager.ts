import * as fs from 'fs';
import * as path from 'path';
import { GenType, UnitTestUpdateStatus } from './type';
import { UT_BASE_PATH } from './const';
import { normalizePath } from './utils';

export class UtFileManager {
  private utBasePath: string = UT_BASE_PATH;
  private projects: string[] = [];
  setProjects(projects: string[]) {
    this.projects = projects;
  }
  async getList(type: GenType, status: UnitTestUpdateStatus): Promise<any[]> {
    const data = await this.getPathContent(type, status);
    const projectDatas = data?.data || {};
    const convertProjectDatas: Record<string, any> = {};
    Object.keys(projectDatas).forEach((projectName) => {
      const projectData = projectDatas[projectName];
      projectData.forEach((item: any) => {
        const projectPath = normalizePath(item.project_path);
        if (convertProjectDatas[projectPath]) {
          convertProjectDatas[projectPath].push(item);
        } else {
          convertProjectDatas[projectPath] = [item];
        }
      });
    });
    let list: any[] = [];
    const projectPaths = this.projects.map((path) => normalizePath(path));
    projectPaths.forEach((projectPath) => {
      const arr = convertProjectDatas[projectPath] || [];
      list = list.concat(arr);
    });
    if (status === UnitTestUpdateStatus.FINISH || status === UnitTestUpdateStatus.ERROR) {
      list.sort((a, b) => b.generate_date.localeCompare(a.generate_date));
    }
    return list;
  }
  private async getPathContent(type: GenType, status: UnitTestUpdateStatus) {
    const filePath = path.join(this.utBasePath, `.progress_gen_by_${type}`, status);
    let str = '';
    if (fs.existsSync(filePath)) {
      str = await fs.promises.readFile(filePath, 'utf8');
    }
    let data: any;
    try {
      data = str ? JSON.parse(str) : {};
    } catch (_error) {}
    return data;
  }
}
