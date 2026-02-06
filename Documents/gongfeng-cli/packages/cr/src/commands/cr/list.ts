import BaseCommand from '../../base';
import { Flags, ux } from '@oclif/core';
import { getUrlWithAdTag, color, shell, truncateHalfAngleString, vars } from '@tencent/gongfeng-cli-base';
import ApiService from '../../api-service';
import { Review4DisplayItem, ReviewWrapperDocFacadeMixIn } from '../../type';
import * as qs from 'qs';
import * as ora from 'ora';
import * as open from 'open';
import Debug from 'debug';
import { ReviewState } from '@tencent/gongfeng-cli-base/dist/gong-feng';

const debug = Debug('gongfeng-cr:list');
const COMMON_SPLITTER = ',';

/**
 * 代码评审列表命令
 */
export default class List extends BaseCommand {
  static summary = '显示仓库下的代码评审';
  static examples = ['gf cr list', 'gf cr list --author zhangsan'];
  static usage = 'cr list [flags]';

  static flags = {
    ...vars.tableFlags(),
    author: Flags.string({
      char: 'A',
      description: '按作者过滤',
      required: false,
      helpGroup: '公共参数',
    }),
    reviewer: Flags.string({
      char: 'r',
      description: '按评审人过滤',
      required: false,
      helpGroup: '公共参数',
    }),
    label: Flags.string({
      char: 'l',
      description: '按标签过滤，同时筛选多个时使用英文逗号(,)分割',
      required: false,
      helpGroup: '公共参数',
    }),
    limit: Flags.integer({
      char: 'L',
      description: '最多显示的代码评审数量',
      default: 20,
      required: false,
      helpGroup: '公共参数',
    }),
    web: Flags.boolean({
      char: 'w',
      description: '打开浏览器查看代码评审列表',
      required: false,
      helpGroup: '公共参数',
    }),
    state: Flags.string({
      char: 's',
      description:
        '按代码评审状态过滤，可选值为“approving|change_required|approved|closed”，同时筛选多个时使用英文逗号(,)分割',
      default: 'approving',
      required: false,
      helpGroup: '公共参数',
    }),
    // path: Flags.string({
    //   char: 'p',
    //   description: '指定路径，例如“/trunk”',
    //   required: false,
    //   helpGroup: 'SVN 代码评审参数',
    // }),
  };
  apiService!: ApiService;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { flags } = await this.parse(List);

    let path = process.cwd();
    path = path.replace(/\\/g, '/');
    debug(`path: ${path}`);
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
      debug(`projectPath: ${project.fullPath}`);

      const { reviewer, author, label, state, limit, web } = flags;
      const usernames = [];
      if (reviewer) {
        usernames.push(reviewer);
      }
      if (author) {
        usernames.push(author);
      }
      const labelIds = label ? await this.getLabelIds(project.id, label.split(COMMON_SPLITTER)) : [];

      let reviewerId;
      let authorId;
      if (usernames.length) {
        const users = await this.apiService.searchUsers(usernames);
        if (reviewer) {
          reviewerId = users.find((user) => user.username === reviewer)?.id;
          if (!reviewerId) {
            console.log(color.warn(__('reviewerNotFound', { username: reviewer })));
          }
        }
        if (author) {
          authorId = users.find((user) => user.username === author)?.id;
          if (!authorId) {
            console.log(color.warn(__('authorNotFound', { username: author })));
          }
        }
      }

      if (web) {
        await this.openInBrowser(project.fullPath, reviewerId, authorId, state, labelIds);
        return;
      }

      const fetchReviewsSpinner = ora().start(__('fetchReviews'));
      const reviews = await this.apiService.searchReviews(project.id, {
        reviewerId,
        authorId,
        reviewStates: this.getReviewStateList(state),
        perPage: limit,
        labelIds,
      });
      fetchReviewsSpinner.stop();
      const reviewTableItems: Review4DisplayItem[] = reviews ? this.buildReviewList(reviews) : [];
      this.printReviewTable(reviewTableItems, flags);
    } else {
      console.log(color.error(__('onlySvnSupported')));
    }
  }

  buildReviewList(reviews: ReviewWrapperDocFacadeMixIn[]) {
    const reviewList: Review4DisplayItem[] = [];
    reviews.forEach((review) => {
      reviewList.push({
        iid: review.iid,
        title: truncateHalfAngleString(review.title, 50),
        author: review.author.username,
        state: review.state,
      });
    });
    return reviewList;
  }

  printReviewTable(items: Review4DisplayItem[], flags: any) {
    if (items.length === 0) {
      console.log(color.warn(__('noReviews')));
      this.exit(0);
      return;
    }
    ux.table(
      items,
      {
        iid: {
          header: __('tableIid'),
          minWidth: 5,
        },
        title: {
          header: __('tableTitle'),
          minWidth: 50,
        },
        author: {
          header: __('tableAuthor'),
          minWidth: 15,
        },
        state: {
          header: __('tableState'),
          get: ({ state }) => {
            return __(state as string);
          },
          minWidth: 15,
        },
      },
      {
        printLine: this.log.bind(this),
        ...flags,
      },
    );
  }

  async openInBrowser(
    projectFullPath: string,
    reviewerId?: number,
    authorId?: number,
    state?: string,
    labelIds?: number[],
  ) {
    const query = qs.stringify({
      reviewer_id: reviewerId,
      author_id: authorId,
      search_type: state,
      label_id: labelIds?.length ? labelIds.join(COMMON_SPLITTER) : undefined,
    });
    let reviewUrl = `https://${vars.host()}/${projectFullPath}/reviews`;
    if (query) {
      reviewUrl += `?${query}`;
    }
    reviewUrl = getUrlWithAdTag(reviewUrl);
    console.log(__('openUrl', { url: reviewUrl }));
    try {
      await open(reviewUrl);
    } catch (e) {
      console.log(color.error(__('openBrowserFailed')));
    }
    return;
  }

  async getLabelIds(projectId: number, labelTitles: string[]) {
    const labelList = await this.apiService.getLabelByTitle(projectId, labelTitles);
    const invalidLabelNames: string[] = [];
    labelTitles.forEach((title) => {
      if (!labelList.find((label) => label.title === title)) {
        invalidLabelNames.push(title);
      }
    });
    if (invalidLabelNames.length) {
      console.log(color.warn(__('invalidLabels', { labels: invalidLabelNames.join(`${COMMON_SPLITTER} `) })));
    }
    return labelList.map((label) => label.id);
  }

  getReviewStateList(state: string) {
    const reviewStateList = state.split(COMMON_SPLITTER);
    if (reviewStateList.includes(ReviewState.CLOSED)) {
      reviewStateList.push(ReviewState.CHANGE_DENIED);
    }
    return [...new Set(reviewStateList)];
  }
}
