import { Project4Detail, getUrlWithAdTag, color, getCurrentRemote, git, vars } from '@tencent/gongfeng-cli-base';
import { Flags, Args } from '@oclif/core';
import Debug from 'debug';
import ApiService from '../../api-service';
import BaseCommand from '../../base';
import { marked } from 'marked';
import * as TerminalRenderer from 'marked-terminal';
import * as gitUrlParse from 'git-url-parse';
import * as ora from 'ora';
import * as open from 'open';

const debug = Debug('gongfeng-repo:show');

/**
 * 项目简介命令
 */
export default class Show extends BaseCommand {
  static summary = '显示仓库的名称和README';
  static description = `不指定仓库时，默认显示当前本地目录对应的远程仓库。
使用“--web”可以直接在浏览器中打开相应仓库查看。`;
  static usage = 'repo show <repository> [flags]';
  static examples = ['gf repo show -w'];

  static args = {
    repository: Args.string({
      required: false,
      description: '指定仓库，参数值使用仓库链接或者“namespace/repo”格式',
    }),
  };

  static flags = {
    web: Flags.boolean({
      char: 'w',
      description: '打开浏览器查看仓库',
      required: false,
    }),
  };

  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { args, flags } = await this.parse(Show);
    const currentPath = process.cwd();

    const repositoryFromArgs = args.repository?.trim() || '';
    let targetProjectPath = repositoryFromArgs;
    // 将项目路径当做链接解析，如果解析报错，则说明不是链接，则按 namespace/repo 格式对待
    try {
      targetProjectPath = gitUrlParse(targetProjectPath).full_name;
    } catch (e) {}
    if (!targetProjectPath) {
      const currentRemote = await getCurrentRemote(currentPath);
      if (!currentRemote) {
        console.log(color.error(__('currentRemoteNotFound')));
        this.exit(0);
        return;
      }
      targetProjectPath = (await git.projectPathFromRemote(currentPath, currentRemote.name)) ?? '';
    }

    const fetchProjectDetailSpinner = ora().start(__('fetchProjectDetail'));
    const projectDetail = await this.apiService.getProjectDetail(targetProjectPath);
    fetchProjectDetailSpinner.stop();
    const projectUrl = getUrlWithAdTag(`https://${vars.host()}/${targetProjectPath}`);
    if (!projectDetail) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    // 在浏览器中打开
    if (flags.web) {
      console.log(__('openUrl', { url: projectUrl }));
      await open(projectUrl);
      return;
    }
    await this.showProjectDetail(projectDetail, projectUrl);
  }

  async showProjectDetail(project: Project4Detail, projectUrl: string) {
    // 仓库名称
    console.log(color.bold(`${project.fullName}`));

    // TODO：仓库描述

    // 仓库 README 内容
    let readmeSection = __('emptyReadme');
    try {
      const readmeContent = await this.apiService.getProjectBlobContent(project.fullPath, {
        path: 'README.md',
        ref: project.defaultBranch,
      });
      readmeSection = this.getReadmeSection(readmeContent);
    } catch (e: any) {
      debug(`readme content fetch error: ${e.message}`);
    }
    console.log(`\n\n\n${readmeSection}`);

    // 仓库链接
    const openUrlSection = color.gray(__('viewRepositoryByUrl', { url: projectUrl }));
    console.log(`\n\n\n${openUrlSection}`);
  }

  getReadmeSection(readmeContent: string) {
    if (!readmeContent) {
      return __('emptyReadme');
    }
    // 高亮
    const markedReadme = marked(readmeContent, { renderer: new TerminalRenderer() });
    const readmeLines = markedReadme.split('\n');
    // 限制输出 30 行
    if (readmeLines.length > 30) {
      return `${readmeLines.slice(0, 30).join('\n')}\n......`;
    }
    return readmeLines.join('\n');
  }
}
