import { Flags, Args } from '@oclif/core';
import BaseCommand from '../../base';
import { shell, color } from '@tencent/gongfeng-cli-base';
import ApiService from '../../api-service';
import { ReviewState } from '@tencent/gongfeng-cli-base/dist/gong-feng';
import * as ora from 'ora';
import Debug from 'debug';

const debug = Debug('gongfeng-cr:close');

export default class Close extends BaseCommand {
  static summary = '关闭一个代码评审';
  static description = '通过指定 iid 关闭一个代码评审';
  static examples = ['gf cr close 123'];
  static usage = 'cr close [iid] [flags]';

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
    const { args, flags } = await this.parse(Close);
    const { iid } = args;
    // 获取当前文件夹的 svn 路径
    let path = process.cwd();
    path = path.replace(/\\/g, '/');
    debug(`path: ${path}`);
    const { comment } = flags;
    if (shell.isSvnPath(path)) {
      const svnBase = shell.getSvnBaseUrl(path);
      debug(`svnBase: ${svnBase}`);
      const fetchSpinner = ora().start(__('fetchProjectDetail'));
      const project = await this.apiService.getSvnProject(svnBase);
      if (!project) {
        console.log(color.error(__('projectNotFound')));
        return;
      }

      // 确认 iid 对应的代码评审存在
      const reviewFacade = await this.getReviewFacade(project.id, iid);
      if (!reviewFacade) {
        fetchSpinner.stop();
        console.log(color.error(__('reviewNotFound', { iid: `${iid}` })));
        this.exit();
        return;
      }
      fetchSpinner.stop();
      const { titleRaw, state } = reviewFacade;
      debug(`reviewState: ${state}`);

      // 如果当前状态有错误，则输出状态错误信息并退出
      const stateErrorMsg = this.getStateErrorMessage(state, iid, titleRaw);
      if (stateErrorMsg) {
        debug(`stateErrorMsg: ${stateErrorMsg}`);
        console.log(stateErrorMsg);
        this.exit(0);
      }

      // 状态无误后再进行关闭操作
      const summary = comment?.trim();
      if (summary) {
        const commentSucceed = await this.apiService.addComment(project.id, iid, summary);
        if (!commentSucceed) {
          console.log(color.error(__('commentFailed')));
        }
      }
      const closeSucceed = await this.apiService.closeReview(project.id, iid);
      if (closeSucceed) {
        console.log(color.success(__('closeReviewSuccess', { iid: `${iid}`, title: titleRaw })));
      } else {
        console.log(color.error(__('closeReviewFailed', { iid: `${iid}`, title: titleRaw })));
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

  getStateErrorMessage(state: ReviewState, iid: number, title: string) {
    let msgKey = 'reviewNotClosable';
    // 如果当前状态为 approving，则不提示错误信息
    if (state === ReviewState.APPROVING || state === ReviewState.REOPENED) {
      return '';
    }
    switch (state) {
      case ReviewState.CLOSED:
        msgKey = 'reviewAlreadyClosed';
        break;
      case ReviewState.APPROVED:
        msgKey = 'reviewAlreadyApproved';
        break;
      case ReviewState.CHANGE_REQUIRED:
        msgKey = 'reviewChangeRequired';
        break;
      case ReviewState.CHANGE_DENIED:
        msgKey = 'reviewChangeDenied';
        break;
      default:
        break;
    }
    return color.warn(__(msgKey, { iid: `${iid}`, title }));
  }
}
