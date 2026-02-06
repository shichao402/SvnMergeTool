import BaseCommand from '../../base';
import { Args, Flags } from '@oclif/core';
import ApiService from '../../api-service';
import { getUrlWithAdTag, color, shell, vars } from '@tencent/gongfeng-cli-base';
import Debug from 'debug';
import { checkCopyFile, filterData, filterStData, getFilesFromDiffSt, MAX_UPLOAD_SIZE } from '../../util';
import * as ora from 'ora';

const debug = Debug('gongfeng-cr:update');

export default class Update extends BaseCommand {
  static summary = '上传修订集(目前只支持 svn 代码在本地模式)';
  static description = '指定代码评审 iid 上传本地变更为代码评审修订集';
  static args = {
    iid: Args.integer({
      required: true,
      description: 'svn 代码评审 iid',
    }),
  };

  static flags = {
    description: Flags.string({
      char: 'd',
      description: '修订集描述',
      helpGroup: '公共参数',
    }),
    author: Flags.string({
      char: 'a',
      description: '指定修订集作者，会展示在评论中：xxx上传了修订集',
      helpGroup: 'SVN 代码评审参数',
    }),
    'only-filename': Flags.boolean({
      description: '只发起文件名评审',
      default: false,
      helpGroup: 'SVN 代码评审参数',
    }),
    files: Flags.string({
      char: 'f',
      description: '指定需评审文件',
      multiple: true,
      helpGroup: 'SVN 代码评审参数',
    }),
    skips: Flags.string({
      char: 's',
      description: '指定需跳过评审的文件',
      multiple: true,
      helpGroup: 'SVN 代码评审参数',
    }),
    encoding: Flags.string({
      char: 'e',
      description: '指定变更编码, 如简体中文：GB18030',
      helpGroup: 'SVN 代码评审参数',
    }),
  };
  apiService!: ApiService;
  public async run() {
    this.apiService = new ApiService(this.api);
    const { args, flags } = await this.parse(Update);
    const { iid } = args;
    let path = process.cwd();
    path = path.replace(/\\/g, '/');
    debug(`iid: ${iid}`);
    debug(`path: ${path}`);
    const { description, files, skips, 'only-filename': onlyFilename, author, encoding } = flags;
    if (shell.isSvnPath(path)) {
      const svnBase = shell.getSvnBaseUrl(path, encoding);
      debug(`svnBase: ${svnBase}`);
      const fetchSpinner = ora().start(__('fetchProjectDetail'));
      const project = await this.apiService.getSvnProject(svnBase);
      if (!project) {
        fetchSpinner.stop();
        console.log(color.error(__('projectNotFound')));
        return;
      }
      debug(`projectPath: ${project.fullPath}`);
      const projectId = project.id;
      let data = '';
      if (!onlyFilename) {
        const diffs = shell.getSvnDiff(path, encoding);
        if (!diffs?.length) {
          fetchSpinner.stop();
          console.log(color.warn(__('noDiff')));
          return;
        }
        const diffFiles = shell.getFilenamesFromDiff(diffs);
        debug('source diffs:');
        debug(diffs);
        debug('source files:');
        debug(diffFiles);
        const [lines, currentFiles] = filterData(path, diffs, diffFiles, files, skips);
        if (!lines?.length) {
          fetchSpinner.stop();
          console.log(color.warn(__('noDiff')));
          return;
        }

        const appendLines = checkCopyFile(path, currentFiles, files);
        lines.push(...appendLines);

        data = lines.join('\r\n');
        debug(`filter diffs: ${data}`);
        debug(`filter files: ${currentFiles.join(', ')}`);
        if (data.length > MAX_UPLOAD_SIZE) {
          fetchSpinner.stop();
          console.log(color.error(__('diffTooLarge')));
          return;
        }
        if (data.length === 0) {
          fetchSpinner.stop();
          console.log(color.error(__('diffEmpty')));
          return;
        }
      } else {
        const diffs = shell.getSvnDiffStat(path, encoding);
        const diffFiles = getFilesFromDiffSt(diffs);
        const [lines, currentFiles] = filterStData(path, diffs, diffFiles, files, skips);
        if (!lines?.length) {
          fetchSpinner.stop();
          console.log(color.warn(__('noDiff')));
          return;
        }

        data = lines.join('\r\n');
        debug(`filter diffs: ${data}`);
        debug(`filter files: ${currentFiles.join(', ')}`);
        if (data.length > MAX_UPLOAD_SIZE) {
          fetchSpinner.stop();
          console.log(color.error(__('diffTooLarge')));
          return;
        }
      }
      fetchSpinner.stop();
      const createSpinner = ora().start(__('updateReviewing'));
      try {
        await this.apiService.createPatchSet(projectId, iid, data, onlyFilename, svnBase, description, author);
        const url = getUrlWithAdTag(`https://${vars.host()}/${project.fullPath}/reviews/${iid}`);
        createSpinner.succeed(__('openCr', { url }));
      } catch (e: any) {
        debug(`createPatchSet error: ${e}`);
        createSpinner.fail(__('updateCrFailed'));
      }
    } else {
      console.log(color.error(__('onlySvnSupported')));
    }
  }
}
