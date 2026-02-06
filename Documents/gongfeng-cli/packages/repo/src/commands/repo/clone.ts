import ApiService from '../../api-service';
import BaseCommand from '../../base';
import * as gitUrlParse from 'git-url-parse';
import { color, vars, git, authToken } from '@tencent/gongfeng-cli-base';
import { ChildProcess } from 'child_process';
import * as split2 from 'split2';
import Debug from 'debug';
import * as ora from 'ora';
import { Args } from '@oclif/core';

const debug = Debug('gongfeng-repo:clone');

/**
 * 克隆项目命令
 */
export default class Clone extends BaseCommand {
  static strict = false;
  static summary = '克隆工蜂仓库到本地';
  static usage = 'repo clone <repository> [-- gitflags...]';
  static examples = ['gf repo clone code/cli'];

  static args = {
    repository: Args.string({
      required: true,
      description: '指定仓库，参数值使用项目链接或者“namespace/repo”格式',
    }),
  };

  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { args, argv } = await this.parse(Clone);
    let repo = args.repository;
    const repoIsUrl = repo.indexOf(':') >= 0;
    if (repoIsUrl) {
      const url = gitUrlParse(repo);
      repo = url.full_name;
    }
    const fetchProjectDetailSpinner = ora().start(__('fetchProjectDetail'));
    const project = await this.apiService.getProjectDetail(repo);
    fetchProjectDetailSpinner.stop();
    if (!project) {
      console.log(`${color.error(__('projectNotFound'))} ${repo}`);
      this.exit();
      return;
    }

    const currentPath = process.cwd();
    const cloneArgs = ['clone'];
    const token = await authToken();
    const repoUrl = `https://oauth2:${token}@${vars.host()}/${repo}.git`;
    cloneArgs.push(repoUrl);
    cloneArgs.push('--progress');

    const gitArgs = argv.splice(1) as string[];
    if (gitArgs?.length) {
      cloneArgs.push(...gitArgs);
    }

    debug(cloneArgs);
    await git.git(cloneArgs, currentPath, 'clone', {
      processCallback: (process: ChildProcess) => {
        if (process?.stderr) {
          process.stderr.pipe(split2()).on('data', (line: string) => {
            console.log(line);
          });
        }
        if (process?.stdout) {
          process.stdout.pipe(split2()).on('data', (line: string) => {
            console.log(line);
          });
        }
      },
    });
  }
}
