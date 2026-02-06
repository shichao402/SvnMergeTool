import {
  Label,
  getUrlWithAdTag,
  color,
  getCurrentRemote,
  git,
  truncateHalfAngleString,
  vars,
} from '@tencent/gongfeng-cli-base';
import BaseCommand from '../../base';
import { ux, Flags } from '@oclif/core';
import ApiService from '../../api-service';
import * as gitUrlParse from 'git-url-parse';
import * as qs from 'qs';
import { IssueFacade } from '../../type';
import * as dayjs from 'dayjs';
import * as ora from 'ora';
import * as open from 'open';

/**
 * issue 列表命令
 */
export default class List extends BaseCommand {
  static summary = '查看项目下的issue列表';
  static usage = 'issue list [flags]';
  static examples = ['gf issue list --label "feature"', 'gf issue list --author zhangsan'];

  static flags = {
    ...vars.tableFlags(),
    assignee: Flags.string({
      char: 'a',
      description: '按负责人过滤',
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
      description: '最多显示的issue数量',
      default: 20,
      required: false,
      helpGroup: '公共参数',
    }),
    state: Flags.string({
      char: 's',
      description: '按issue状态过滤，可选值为“opened|closed|all',
      default: 'opened',
      required: false,
      helpGroup: '公共参数',
    }),
    web: Flags.boolean({
      char: 'w',
      description: '打开浏览器查看issue列表',
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

    let targetProjectPath = flags.repo ? gitUrlParse(flags.repo).full_name : '';
    console.log(targetProjectPath);
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
    if (!projectDetail) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    const usernames = [];
    const { assignee, author, label, limit, state, web } = flags;
    if (assignee) {
      usernames.push(assignee);
    }
    if (author) {
      usernames.push(author);
    }

    let assigneeId;
    let authorId;
    if (usernames.length) {
      const users = await this.apiService.searchUsers(usernames);
      if (assignee) {
        assigneeId = users.find((user) => user.username === assignee)?.id;
      }
      if (author) {
        authorId = users.find((user) => user.username === author)?.id;
      }
    }

    if (web) {
      const params = {
        assignee_id: assigneeId,
        author_id: authorId,
        state,
        label_name: label,
      };
      const query = qs.stringify(params);
      let url = `https://${vars.host()}/${targetProjectPath}/issues`;
      if (query) {
        url = `${url}?${query}`;
      }
      url = getUrlWithAdTag(url);
      console.log(__('openUrl', { url }));
      await open(url);
      return;
    }

    const fetchIssuesSpinner = ora().start(__('fetchIssues'));
    const issues = await this.apiService.searchIssues(projectDetail.id, assigneeId, authorId, state, label, limit);
    fetchIssuesSpinner.stop();
    if (!issues?.length) {
      console.log(color.warn(__('noIssues', { projectPath: targetProjectPath })));
      this.exit(0);
      return;
    }

    ux.table(
      this.buildIssues(issues),
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
        labels: {
          header: __('labels'),
          minWidth: 15,
          get: ({ labels }: { labels: Label[] }) => {
            const labelsString = labels
              .map((label) => {
                return label.title;
              })
              .join(', ');
            return truncateHalfAngleString(labelsString, 15);
          },
        },
        state: {
          header: __('state'),
          get: ({ state }: { state: string }) => {
            return __(state);
          },
          minWidth: 15,
        },
        createdAt: {
          header: __('createdAt'),
          minWidth: 25,
          get: ({ createdAt }: { createdAt: number }) => {
            return dayjs(createdAt).format(vars.timeFormatter);
          },
        },
      },
      {
        printLine: this.log.bind(this),
        ...flags,
      },
    );
  }

  buildIssues(issues: IssueFacade[]) {
    const formattedIssues: Record<string, unknown>[] = [];
    issues.forEach((issueFacade) => {
      const issue = {
        iid: issueFacade.iid,
        title: truncateHalfAngleString(issueFacade.titleRaw, 50),
        author: issueFacade.author.username,
        labels: issueFacade.labels,
        state: issueFacade.state,
        createdAt: issueFacade.createdAt,
      };
      formattedIssues.push(issue);
    });
    return formattedIssues;
  }
}
