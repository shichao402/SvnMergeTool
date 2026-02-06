import BaseCommand from '../../base';
import { ux, Flags } from '@oclif/core';
import { color, getCurrentRemote, git, loginUser, vars } from '@tencent/gongfeng-cli-base';
import ApiService from '../../api-service';
import { MergeRequestFacade, ReadyMergeRequest } from '../../type';
import { getCommitCheckerOverviewStatus } from '../../util';
import * as ora from 'ora';

/**
 * 与登录人相关的合并请求
 */
export default class Status extends BaseCommand {
  static summary = '显示与我相关的合并请求';
  static examples = ['gf mr status', 'gf mr status --R namespace/repo'];
  static usage = 'mr status [flags]';

  static flags = {
    ...vars.tableFlags(),
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
    const { flags } = await this.parse(Status);
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
      targetProjectPath = (await git.projectPathFromRemote(currentPath, currentRemote?.name)) ?? '';
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

    const username = await loginUser();
    if (!username) {
      console.log(color.bold(color.warn('使用工蜂CLI前，请先执行"gf auth login" (别名: "gf login")登录工蜂CLI!')));
      this.exit(0);
      return;
    }
    const users = await this.apiService.searchUsers([username]);
    if (!users.length) {
      console.log(color.bold(color.warn(__('userNotFound', { username }))));
      this.exit(0);
      return;
    }
    const userId = users[0].id;
    const fetchMergeRequestsSpinner = ora().start(__('fetchMergeRequests'));
    const reviewMergeRequests = await this.apiService.searchMergeRequestByReviewer(targetProject.id, userId);
    const mineMergeRequests = await this.apiService.searchMergeRequestByAuthor(targetProject.id, userId);
    const readyMergeRequests = await this.apiService.searchMergeRequestReadyToMerge(targetProject.id, userId);
    fetchMergeRequestsSpinner.stop();

    if (mineMergeRequests?.length) {
      console.log(`\n${color.bold(__('createdByYou'))}`);
      ux.table(
        this.buildMergeRequests(mineMergeRequests),
        {
          iid: {
            header: 'iid',
            minWidth: 5,
          },
          title: {
            header: __('title'),
            minWidth: 30,
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

    if (reviewMergeRequests?.length) {
      console.log(`\n${color.bold(__('iAmReviewer'))}`);
      ux.table(
        this.buildMergeRequests(reviewMergeRequests),
        {
          iid: {
            header: 'iid',
            minWidth: 5,
          },
          title: {
            header: __('title'),
            minWidth: 30,
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

    if (readyMergeRequests?.length) {
      console.log(`\n${color.bold(__('readyToMerge'))}`);
      ux.table(
        this.buildReadyMergeRequests(readyMergeRequests),
        {
          iid: {
            header: 'iid',
            minWidth: 5,
          },
          title: {
            header: __('title'),
            minWidth: 30,
          },
          author: {
            header: __('authorTitle'),
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
  }

  buildMergeRequests(mergeRequests: MergeRequestFacade[]) {
    const mrs: Record<string, unknown>[] = [];
    mergeRequests.forEach((mr) => {
      const mergeRequest = {
        iid: mr.mergeRequest.iid,
        title: mr.mergeRequest.titleRaw,
        author: mr.mergeRequest.author.username,
        state: mr.mergeRequest.state,
        check: getCommitCheckerOverviewStatus(mr.commitChecks),
        note: mr.noteCount,
      };
      mrs.push(mergeRequest);
    });
    return mrs;
  }

  buildReadyMergeRequests(mergeRequests: ReadyMergeRequest[]) {
    const mrs: Record<string, unknown>[] = [];
    mergeRequests.forEach((mr) => {
      const mergeRequest = {
        iid: mr.iid,
        title: mr.title,
        author: mr.author.username,
        check: getCommitCheckerOverviewStatus(mr.commitChecks),
        note: mr.noteCount,
      };
      mrs.push(mergeRequest);
    });
    return mrs;
  }
}
