import BaseCommand from '../../base';
import { ux, Flags } from '@oclif/core';
import {
  color,
  getCurrentRemote,
  git,
  vars,
  truncateHalfAngleString,
  getUrlWithAdTag,
} from '@tencent/gongfeng-cli-base';
import ApiService from '../../api-service';
import * as qs from 'qs';
import { MergeRequestFacade } from '../../type';
import { getCommitCheckerOverviewStatus } from '../../util';
import * as ora from 'ora';
import * as open from 'open';

/**
 * 合并请求列表命令
 */
export default class List extends BaseCommand {
  static summary = '显示仓库下的合并请求';
  static examples = ['gf mr list', 'gf mr list --author zhangsan'];
  static usage = 'mr list [flags]';

  static flags = {
    ...vars.tableFlags(),
    assignee: Flags.string({
      char: 'a',
      description: '按合并负责人过滤',
      required: false,
      helpGroup: '公共参数',
    }),
    reviewer: Flags.string({
      char: 'r',
      description: '按评审人过滤',
      required: false,
      helpGroup: '公共参数',
    }),
    author: Flags.string({
      char: 'A',
      description: '按作者过滤',
      required: false,
      helpGroup: '公共参数',
    }),
    label: Flags.string({
      char: 'l',
      description: '按标签过滤',
      required: false,
      helpGroup: '公共参数',
    }),
    limit: Flags.integer({
      char: 'L',
      description: '最多显示的合并请求数量',
      default: 20,
      required: false,
      helpGroup: '公共参数',
    }),
    target: Flags.string({
      char: 'T',
      description: '按目标分支过滤',
      required: false,
      helpGroup: '公共参数',
    }),
    state: Flags.string({
      char: 's',
      description: '按合并请求状态过滤，可选值为“opened|merged|closed|all”',
      default: 'opened',
      required: false,
      helpGroup: '公共参数',
    }),
    web: Flags.boolean({
      char: 'w',
      description: '打开浏览器查看合并请求列表',
      required: false,
      helpGroup: '公共参数',
    }),
    repo: Flags.string({
      char: 'R',
      description: '指定仓库，参数值使用“namespace/repo”的格式',
      required: false,
      helpGroup: '公共参数',
    }),
  };
  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { flags } = await this.parse(List);
    const currentPath = process.cwd();

    let targetProjectPath = '';
    if (flags.repo) {
      targetProjectPath = flags.repo.trim();
    } else {
      const currentRemote = await getCurrentRemote(currentPath);
      if (!currentRemote) {
        console.log(color.error(__('currentRemoteNotFound')));
        this.exit(0);
        return;
      }
      targetProjectPath = (await git.projectPathFromRemote(currentPath, currentRemote.name)) ?? '';
    }

    if (!targetProjectPath) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    const fetchProjectDetailSpinner = ora().start(__('fetchProjectDetail'));
    const targetProject = await this.apiService.getProjectDetail(targetProjectPath);
    fetchProjectDetailSpinner.stop();
    if (!targetProject) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    const usernames = [];
    const { assignee, reviewer, author, label, target, state, limit, web } = flags;
    if (assignee) {
      usernames.push(assignee);
    }
    if (reviewer) {
      usernames.push(reviewer);
    }
    if (author) {
      usernames.push(author);
    }

    let assigneeId;
    let reviewerId;
    let authorId;
    if (usernames.length) {
      const users = await this.apiService.searchUsers(usernames);
      if (assignee) {
        assigneeId = users.find((user) => user.username === assignee)?.id;
      }
      if (reviewer) {
        reviewerId = users.find((user) => user.username === reviewer)?.id;
      }
      if (author) {
        authorId = users.find((user) => user.username === author)?.id;
      }
    }

    if (web) {
      const params = {
        assignee_id: assigneeId,
        reviewer_id: reviewerId,
        author_id: authorId,
        state,
        branch: target,
        label_name: label,
      };
      const query = qs.stringify(params);
      let url = getUrlWithAdTag(`https://${vars.host()}/${targetProjectPath}/merge_requests`);
      if (query) {
        url = `${url}?${query}`;
      }
      console.log(__('openUrl', { url }));
      await open(url);
      return;
    }

    const fetchMergeRequestsSpinner = ora().start(__('fetchMergeRequests'));
    const mergeRequests = await this.apiService.searchMergeRequests(
      targetProject.id,
      assigneeId,
      reviewerId,
      authorId,
      state,
      target,
      label,
      limit,
    );
    fetchMergeRequestsSpinner.stop();
    if (!mergeRequests?.length) {
      console.log(color.warn(__('noMergeRequests', { projectPath: targetProjectPath })));
      this.exit(0);
      return;
    }

    ux.table(
      this.buildMergeRequests(mergeRequests),
      {
        iid: {
          header: 'iid',
          minWidth: 5,
        },
        title: {
          header: __('title'),
          minWidth: 50,
        },
        author: {
          header: __('authorTitle'),
          minWidth: 15,
        },
        state: {
          header: __('state'),
          get: ({ state }) => {
            return __(state as string);
          },
          minWidth: 15,
        },
        check: {
          header: __('check'),
          minWidth: 15,
        },
        note: {
          header: __('note'),
          minWidth: 15,
          extended: true,
        },
      },
      {
        printLine: this.log.bind(this),
        ...flags,
      },
    );
  }

  buildMergeRequests(mergeRequests: MergeRequestFacade[]) {
    const mrs: Record<string, unknown>[] = [];
    mergeRequests.forEach((mr) => {
      const mergeRequest = {
        iid: mr.mergeRequest.iid,
        title: truncateHalfAngleString(mr.mergeRequest.titleRaw, 50),
        author: mr.mergeRequest.author.username,
        state: mr.mergeRequest.state,
        check: getCommitCheckerOverviewStatus(mr.commitChecks),
        note: mr.noteCount,
      };
      mrs.push(mergeRequest);
    });
    return mrs;
  }
}
