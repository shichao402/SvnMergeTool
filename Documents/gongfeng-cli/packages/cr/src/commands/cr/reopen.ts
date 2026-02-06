import { Flags, Args } from '@oclif/core';
import BaseCommand from '../../base';
import { shell, color } from '@tencent/gongfeng-cli-base';
import ApiService from '../../api-service';
import { ReviewState } from '@tencent/gongfeng-cli-base/dist/gong-feng';
import * as ora from 'ora';
import Debug from 'debug';

const debug = Debug('gongfeng-cr:reopen');

export default class Reopen extends BaseCommand {
  static summary = '重新打开一个代码评审';
  static description = '通过指定 iid 重新打开一个代码评审';
  static examples = ['gf cr reopen 123'];
  static usage = 'cr reopen [iid] [flags]';

  static args = {
    iid: Args.integer({
      required: true,
      description: '代码评审 iid',
    }),
  };

  static flags = {
    comment: Flags.string({
      char: 'c',
      description: '关闭的同时发表一条评论',
    }),
  };

  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { args, flags } = await this.parse(Reopen);
    const { iid } = args;
    // 获取当前文件夹的 svn 路径
    let path = process.cwd();
    path = path.replace(/\\/g, '/');
    const { comment } = flags;
    if (shell.isSvnPath(path)) {
      const svnBase = shell.getSvnBaseUrl(path);
      debug(`svnBase: ${svnBase}`);
      const fetchSpinner = ora().start(__('fetchProjectDetail'));
      const project = await this.apiService.getSvnProject(svnBase);
      if (!project) {
        fetchSpinner.stop();
        console.log(color.error(__('projectNotFound')));
        return;
      }
      fetchSpinner.stop();

      // 确认 iid 对应的代码评审存在
      const reviewFacade = await this.getReviewFacade(project.id, iid);
      if (!reviewFacade) {
        console.log(color.error(__('reviewNotFound', { iid: `${iid}` })));
        this.exit();
        return;
      }
      const { titleRaw, state } = reviewFacade;
      debug(`reviewState: ${state}`);

      // cr 已处于评审状态
      if (state === ReviewState.REOPENED || state === ReviewState.APPROVING) {
        console.log(color.warn(__('reviewAlreadyApproving', { iid: `${iid}`, title: titleRaw })));
        this.exit(0);
        return;
      }

      const summary = comment?.trim();
      if (summary) {
        const commentSucceed = await this.apiService.addComment(project.id, iid, summary);
        if (!commentSucceed) {
          console.log(color.error(__('commentFailed')));
        }
      }
      const reopenSucceed = await this.apiService.reopenReview(project.id, iid);
      if (reopenSucceed) {
        console.log(color.success(__('reopenReviewSuccess', { iid: `${iid}`, title: titleRaw })));
      } else {
        console.log(color.error(__('reopenReviewFailed', { iid: `${iid}`, title: titleRaw })));
      }
    } else {
      console.log(color.error(__('onlySvnSupported')));
    }
  }

  async getReviewFacade(projectId: number, reviewIid: number) {
    try {
      const reviewFacade = this.apiService.getReviewFacade(projectId, reviewIid);
      return reviewFacade;
    } catch (e) {
      console.log(color.error(__('reviewNotFound', { iid: `${reviewIid}` })));
      this.exit();
      return;
    }
  }
}
