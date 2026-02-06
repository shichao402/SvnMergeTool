import { MergeRequestState } from './../../type';
import { Flags, Args } from '@oclif/core';
import BaseCommand from '../../base';
import { color, getCurrentRemote, git } from '@tencent/gongfeng-cli-base';
import Debug from 'debug';
import ApiService from '../../api-service';
import { isCurrentUserCanEditMr, isNumeric } from '../../util';

const debug = Debug('gongfeng-mr:close');

/**
 * 合并请求关闭命令
 */
export default class Close extends BaseCommand {
  static summary = '关闭一个合并请求';
  static description = `可以通过 iid 或者源分支指定需要关闭的合并请求
  当通过源分支指定时默认关闭源分支最新的合并请求`;
  static examples = ['gf mr close 42', 'gf mr close dev'];
  static usage = 'mr close [iidOrBranch] [flags]';

  static args = {
    iidOrBranch: Args.string({
      required: true,
      description: '合并请求 iid 或者源分支名称',
    }),
  };

  static flags = {
    comment: Flags.string({
      char: 'c',
      description: '关闭的同时发表一条评论',
      required: false,
    }),
    repo: Flags.string({
      char: 'R',
      description: '指定仓库，参数值使用“namespace/repo”的格式',
      required: false,
    }),
  };

  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const currentPath = process.cwd();
    const { args, flags } = await this.parse(Close);

    let targetProjectPath: string | null = '';
    if (flags.repo) {
      targetProjectPath = flags.repo.trim();
    } else {
      const currentRemote = await getCurrentRemote(currentPath);
      if (!currentRemote) {
        console.log(color.error(__('currentRemoteNotFound')));
        this.exit(0);
        return;
      }
      targetProjectPath = await git.projectPathFromRemote(currentPath, currentRemote.name);
    }

    debug(`target project path: ${targetProjectPath}`);

    if (!targetProjectPath) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    const targetProject = await this.apiService.getProjectDetail(targetProjectPath);
    if (!targetProject) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    debug(`target project full path: ${targetProject.fullPath}`);

    const projectId = targetProject.id;
    const branch = args.iidOrBranch;
    const mergeRequest4Detail = await this.apiService.getMergeRequest4DetailByIidOrBranch(projectId, branch);
    if (!mergeRequest4Detail) {
      if (isNumeric(branch)) {
        console.log(color.error(__('mergeRequestNotFound', { iidOrBranch: branch })));
      } else {
        console.log(color.error(__('mergeRequestNotFoundForBranch', { branch })));
      }
      this.exit(0);
      return;
    }

    debug(`mr iid: ${mergeRequest4Detail.mergeRequest.iid}`);

    if (!isCurrentUserCanEditMr(mergeRequest4Detail)) {
      console.log(color.error(__('noPermissionUpdateMr')));
      this.exit(0);
    }

    const { mergeRequest, review } = mergeRequest4Detail;
    if (mergeRequest.state === MergeRequestState.CLOSED) {
      console.log(
        color.warn(__('mergeRequestAlreadyClosed', { iid: `${mergeRequest.iid}`, title: mergeRequest.titleRaw })),
      );
      this.exit(0);
      return;
    }
    // mr 已被合并
    if (mergeRequest.state === MergeRequestState.MERGED) {
      console.log(color.warn(__('mergedCloseError', { iid: `${mergeRequest.iid}`, title: mergeRequest.titleRaw })));
      this.exit(0);
      return;
    }
    // mr 已被锁定
    if (mergeRequest.state === MergeRequestState.LOCKED) {
      console.log(color.warn(__('lockedCloseError', { iid: `${mergeRequest.iid}`, title: mergeRequest.titleRaw })));
      this.exit(0);
      return;
    }

    const comment = flags.comment?.trim();
    // 如果有评论参数，则添加评论
    if (comment) {
      const isSucceed = await this.apiService.patchReviewerSummary(projectId, review.iid, comment);
      if (!isSucceed) {
        console.log(color.error(__('commentError')));
      }
    }
    const isSucceed = await this.apiService.closeMergeRequest(projectId, mergeRequest.iid);
    if (isSucceed) {
      console.log(
        color.success(__('closedMergeRequest', { iid: `${mergeRequest.iid}`, title: mergeRequest.titleRaw })),
      );
    } else {
      console.log(
        color.error(__('closeMergeRequestError', { iid: `${mergeRequest.iid}`, title: mergeRequest.titleRaw })),
      );
    }
  }
}
