import { Flags, Args } from '@oclif/core';
import BaseCommand from '../../base';
import ApiService from '../../api-service';
import * as gitUrlParse from 'git-url-parse';
import { Project4Detail, getUrlWithAdTag, color, getCurrentRemote, git, vars } from '@tencent/gongfeng-cli-base';
import { IssueFacade, IssueState } from '../../type';
import * as dayjs from 'dayjs';
import * as ora from 'ora';
import * as open from 'open';

/**
 * issue 详情信息命令
 */
export default class Show extends BaseCommand {
  static summary = '查看 issue 的详细信息';
  static usage = 'issue show <iid> [flags]';
  static examples = ['gf issue show 1 -w'];

  static args = {
    iid: Args.integer({
      description: '议题的iid',
      required: true,
    }),
  };
  static flags = {
    web: Flags.boolean({
      char: 'w',
      description: '打开浏览器查看issue',
    }),
    repo: Flags.string({
      char: 'R',
      description: '指定仓库，参数值使用“namespace/repo”的格式',
      required: false,
    }),
  };
  apiService!: ApiService;
  projectDetail: Project4Detail | null = null;

  async run(): Promise<void> {
    this.apiService = new ApiService(this.api);
    const { args, flags } = await this.parse(Show);
    const { iid } = args;
    const { web, repo } = flags;
    const currentPath = process.cwd();

    let targetProjectPath = repo ? gitUrlParse(repo).full_name : '';
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
    this.projectDetail = await this.apiService.getProjectDetail(targetProjectPath);
    fetchProjectDetailSpinner.stop();
    if (!this.projectDetail) {
      console.log(`${color.error(__('projectNotFound'))} ${targetProjectPath}`);
      this.exit();
      return;
    }

    const projectId = this.projectDetail.id;
    const fetchIssueDetailSpinner = ora().start(__('fetchIssueDetail'));
    const issueDetail = await this.apiService.getIssueDetailByIid(projectId, iid);
    fetchIssueDetailSpinner.stop();
    if (!issueDetail) {
      console.log(__('issueNotFound', { iid: `${iid}` }));
      return;
    }

    if (web) {
      const issueUrl = this.getIssueUrl(issueDetail);
      console.log(__('openUrl', { url: issueUrl }));
      await open(issueUrl);
      return;
    }

    this.showIssueDetail(issueDetail);
  }

  showIssueDetail(issueDetail: IssueFacade) {
    const { state, iid, titleRaw, author, createdAt, description, labels, assignees } = issueDetail;
    const sections = [];
    const requiredInfos = [
      // 打开•[#1] issue 标题
      `${this.getColoredIssueState(state)}•[#${iid}] ${titleRaw}`,
      // xx 于 YYYY-MM-DD hh:mm:ss 创建
      `${__('userCreatedAt', {
        username: author.username,
        createdAt: dayjs(createdAt).format(vars.timeFormatter),
      })}`,
      // issue描述
      `${description}`,
    ].join('\n');

    // 此部分信息可能为空
    const optionalInfos = [];
    if (labels?.length) {
      const labelsStr = labels.map((label) => label.title).join(', ');
      optionalInfos.push(`${__('labels')}: ${labelsStr}`);
    }
    if (assignees?.length) {
      const assigneesName = assignees.map((assignee) => assignee.username).join(', ');
      optionalInfos.push(`${__('assignees')}: ${assigneesName}`);
    }

    // 浏览器打开查看issue
    const viewIssueByUrl = color.gray(__('viewIssueByUrl', { url: this.getIssueUrl(issueDetail) }));

    sections.push(requiredInfos);
    // 当 optionalInfos 不为空时才向 sections 中插入
    optionalInfos.length && sections.push(optionalInfos.join('\n'));
    sections.push(viewIssueByUrl);

    // 输出拼装好的信息，每部分信息之间空两行分隔，每部分换行本身还需要一个 \n，因此需要 3 个 \n
    console.log(sections.join('\n\n\n'));
  }

  getIssueUrl(issueDetail: IssueFacade) {
    if (!this.projectDetail) return '';
    const { fullPath } = this.projectDetail;
    const { iid } = issueDetail;
    return getUrlWithAdTag(`https://${vars.host()}/${fullPath}/issues/${iid}`);
  }

  getColoredIssueState(state: IssueState) {
    switch (state) {
      case IssueState.CLOSED: {
        return color.error(__(state));
      }
      case IssueState.OPENED:
      case IssueState.REOPENED: {
        return color.success(__(state));
      }
      default: {
        return __(state);
      }
    }
  }
}
