import { Flags, Args } from '@oclif/core';
import ApiService from '../../api-service';
import BaseCommand from '../../base';
import { Project4Detail, getUrlWithAdTag, color, getCurrentRemote, git, vars } from '@tencent/gongfeng-cli-base';
import * as gitUrlParse from 'git-url-parse';
import { TagReleaseFacade } from '../../type';
import * as dayjs from 'dayjs';
import * as ora from 'ora';
import * as open from 'open';

/**
 * release 详情命令
 */
export default class Show extends BaseCommand {
  static summary = '查看release的详细信息';
  static usage = 'release show <release title> [flags]';
  static examples = ['gf release show v1.5.0 -w'];

  static args = {
    releaseTitle: Args.string({
      required: true,
      description: 'release的标题',
    }),
  };

  static flags = {
    web: Flags.boolean({
      char: 'w',
      description: '打开浏览器查看 release 详细信息',
      required: false,
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
    const { releaseTitle } = args;
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
    const fetchReleaseDetailSpinner = ora().start(__('fetchReleaseDetail'));
    const releaseDetail = await this.apiService.getReleaseByTagName(projectId, releaseTitle);
    fetchReleaseDetailSpinner.stop();
    if (!releaseDetail) {
      console.log(__('releaseNotFound', { releaseTitle }));
      return;
    }

    if (web) {
      const releaseUrl = this.getReleaseUrl(releaseDetail);
      console.log(__('openUrl', { url: releaseUrl }));
      await open(releaseUrl);
      return;
    }

    this.showReleaseDetail(releaseDetail);
  }

  showReleaseDetail(releaseDetail: TagReleaseFacade) {
    const { labels, release, ref, attachments } = releaseDetail;
    const sections = [];
    const requiredInfos = [
      release.tag,
      // xx 于 YYYY-MM-DD hh:mm:ss 创建
      `${__('userCreatedAt', {
        username: release.author.username,
        createdAt: dayjs(release.createdAt).format(vars.timeFormatter),
      })}`,
      `${__('createFrom')}: ${ref.commit.objectId.slice(0, 6)}`,
    ];
    // Tag Message
    if (ref.extraMessage) {
      requiredInfos.push(`${__('tagMessage')}: ${ref.extraMessage}`);
    }
    if (release.description) {
      requiredInfos.push(release.description);
    }

    const optionalInfos = [];
    if (labels?.length) {
      const labelsStr = labels.map((label) => label.title).join(', ');
      optionalInfos.push(`${__('labels')}: ${labelsStr}`);
    }
    if (attachments?.length) {
      const attachmentNamesStr = attachments.map((attachment) => `${attachment.name}`).join(', ');
      optionalInfos.push(`${__('attachments')}: ${attachmentNamesStr}`);
    }

    // 浏览器打开查看 release
    const viewReleaseByUrl = color.gray(__('viewReleaseByUrl', { url: this.getReleaseUrl(releaseDetail) }));

    sections.push(requiredInfos.filter(Boolean).join('\n'));
    // 当 optionalInfos 不为空时才向 sections 中插入
    optionalInfos.length && sections.push(optionalInfos.join('\n'));
    sections.push(viewReleaseByUrl);

    // 输出拼装好的信息，每部分信息之间空两行分隔，每部分换行本身还需要一个 \n，因此需要 3 个 \n
    console.log(sections.join('\n\n\n'));
  }

  getReleaseUrl(tagReleaseFacade: TagReleaseFacade) {
    if (!this.projectDetail || !tagReleaseFacade.release) return '';
    const { fullPath } = this.projectDetail;
    return getUrlWithAdTag(`https://${vars.host()}/${fullPath}/-/releases/${tagReleaseFacade.release.tag}`);
  }
}
