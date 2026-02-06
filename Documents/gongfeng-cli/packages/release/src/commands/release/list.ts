import { ux, Flags } from '@oclif/core';
import {
  Label,
  getUrlWithAdTag,
  color,
  getCurrentRemote,
  git,
  truncateHalfAngleString,
  vars,
} from '@tencent/gongfeng-cli-base';
import ApiService from '../../api-service';
import BaseCommand from '../../base';
import * as gitUrlParse from 'git-url-parse';
import * as qs from 'qs';
import { TagReleaseFacade } from '../../type';
import * as ora from 'ora';
import * as open from 'open';

/**
 * releas 列表命令
 */
export default class List extends BaseCommand {
  static summary = '查看仓库下的 release';
  static usage = 'release list [flags]';
  static examples = ['gf release list'];

  static flags = {
    ...vars.tableFlags(),
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
      description: '最多显示的 release 数量',
      default: 20,
      required: false,
      helpGroup: '公共参数',
    }),
    web: Flags.boolean({
      char: 'w',
      description: '打开浏览器查看 release 列表',
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
    const { author, label, web, limit } = flags;
    if (author) {
      usernames.push(author);
    }

    let authorId;
    if (usernames.length) {
      const users = await this.apiService.searchUsers(usernames);
      if (author) {
        authorId = users.find((user) => user.username === author)?.id;
      }
    }

    if (web) {
      const params = {
        author_id: authorId,
        label_name: label,
      };
      const query = qs.stringify(params);
      let url = `https://${vars.host()}/${targetProjectPath}/-/releases`;
      if (query) {
        url = `${url}?${query}`;
      }
      url = getUrlWithAdTag(url);
      console.log(__('openUrl', { url }));
      await open(url);
      return;
    }

    const fetchReleasesSpinner = ora().start(__('fetchReleases'));
    const releases = await this.apiService.searchReleases(
      projectDetail.id,
      limit,
      authorId,
      label ? [label] : undefined,
    );
    fetchReleasesSpinner.stop();
    if (!releases?.length) {
      console.log(color.warn(__('noReleases', { projectPath: targetProjectPath })));
      this.exit(0);
      return;
    }

    ux.table(
      this.buildReleases(releases),
      {
        title: {
          header: __('title'),
          minWidth: 20,
        },
        createFrom: {
          header: __('createFrom'),
          minWidth: 15,
        },
        message: {
          header: __('tagMessage'),
          minWidth: 50,
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
      },
      {
        printLine: this.log.bind(this),
        ...flags,
      },
    );
  }

  buildReleases(tagReleases: TagReleaseFacade[]) {
    const formattedReleases: Record<string, unknown>[] = [];
    tagReleases.forEach((tagRelease) => {
      const { release, ref, labels } = tagRelease;
      const formattedRelease = {
        title: truncateHalfAngleString(release.tag, 20),
        message: truncateHalfAngleString(ref.extraMessage || '', 50),
        createFrom: ref.commit.objectId.slice(0, 6),
        labels,
      };
      formattedReleases.push(formattedRelease);
    });
    return formattedReleases;
  }
}
