import { Flags, Args } from '@oclif/core';
import BaseCommand from '../../base';
import {
  color,
  getCurrentRemote,
  Remote,
  vars,
  git,
  Models,
  loginUser,
  cloneTokenCompo,
} from '@tencent/gongfeng-cli-base';
import Debug from 'debug';
import ApiService from '../../api-service';
import { consoleProcessCallback, isNumeric } from '../../util';
import * as ora from 'ora';

const debug = Debug('gongfeng-mr:checkout');

/**
 * 合并请求检出命令
 */
export default class Checkout extends BaseCommand {
  static summary = '检出合并请求源分支';
  static description = '从远程仓库检出合并请求源分支到本地。';
  static examples = ['gf mr checkout 42', 'gf mr checkout dev'];
  static usage = 'mr checkout <iidOrBranch> [flags]';

  static args = {
    iidOrBranch: Args.string({
      required: true,
      description: '合并请求 id 或者源分支名称',
    }),
  };

  static flags = {
    branch: Flags.string({
      char: 'b',
      description: '本地分支使用的名称（默认为合并请求源分支名称）',
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
    const { args, flags } = await this.parse(Checkout);

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
    const targetRemote = await git.findRemoteByProjectPath(currentPath, targetProjectPath);
    let sourceRemote = targetRemote;
    const branch = args.iidOrBranch;
    let sourceProject = targetProject;
    let sourceBranch = branch;
    if (isNumeric(branch)) {
      const iid = parseInt(branch, 10);
      const fetchMergeRequestDetailSpinner = ora().start(__('fetchMergeRequestDetail'));
      const mergeRequest4Detail = await this.apiService.getMergeRequestByIid(targetProject.id, iid);
      fetchMergeRequestDetailSpinner.stop();
      if (mergeRequest4Detail) {
        if (mergeRequest4Detail.mergeRequest.targetProjectId !== mergeRequest4Detail.mergeRequest.sourceProjectId) {
          sourceProject = mergeRequest4Detail.sourceProject;
          sourceRemote = await git.findRemoteByProjectPath(currentPath, sourceProject.fullPath);
        }
        sourceBranch = mergeRequest4Detail.mergeRequest.sourceBranch;

        if (mergeRequest4Detail.mergeRequest.prePushMR) {
          console.log(color.error(__('prePushNotSupported')));
          this.exit(0);
        }

        if (!mergeRequest4Detail.sourceBranchExist) {
          console.log(color.error(__('sourceBranchDeleted')));
          this.exit(0);
        }
      }
    }

    const sourceFetchUrl = `https://${await cloneTokenCompo()}@${vars.host()}/${sourceProject.fullPath}.git`;
    let sourceUrlOrName = `https://${vars.host()}/${sourceProject.fullPath}.git`;
    if (sourceRemote) {
      sourceUrlOrName = sourceRemote.name;
    }
    debug(`sourceUrlOrName: ${sourceUrlOrName}`);
    debug(`sourceBranch: ${sourceBranch}`);

    if (sourceRemote) {
      await this.cmds4ExistingRemote(currentPath, sourceRemote, sourceFetchUrl, sourceBranch, flags.branch);
    } else {
      await this.cmds4MissingRemote(
        currentPath,
        sourceBranch,
        sourceUrlOrName,
        sourceFetchUrl,
        targetProject.defaultBranch,
        flags.branch,
      );
    }
  }

  async cmds4MissingRemote(
    currentPath: string,
    sourceBranch: string,
    sourceUrlOrName: string,
    sourceFetchUrl: string,
    defaultBranch: string,
    branchFlag?: string,
  ) {
    const ref = sourceBranch;
    let localBranch = sourceBranch;
    if (branchFlag) {
      localBranch = branchFlag;
    } else if (sourceBranch === defaultBranch) {
      // 避免覆盖默认分支
      const user = await loginUser();
      localBranch = `${user}/${localBranch}`;
    }
    debug(`localBranch: ${localBranch}`);
    const currentBranch = await git.getCurrentBranch(currentPath);
    if (localBranch === currentBranch) {
      const result = await git.fetchRefspec(currentPath, sourceFetchUrl, ref, consoleProcessCallback);
      if (result?.exitCode === 0) {
        await git.git(['merge', '--ff-only', 'FETCH_HEAD'], currentPath, 'mergeFetchHead', {
          processCallback: consoleProcessCallback,
        });
      } else {
        this.exit(0);
        return;
      }
    } else {
      const branches = await git.getBranches(currentPath);
      const branch = branches.find((b: Models.Branch) => b.name === localBranch);
      const result = await git.fetchRefspec(
        currentPath,
        sourceFetchUrl,
        `${ref}:${localBranch}`,
        consoleProcessCallback,
      );
      if (result?.exitCode === 0) {
        if (branch) {
          await git.git(['checkout', branch.name], currentPath, 'checkoutBranch', {
            processCallback: consoleProcessCallback,
          });
        } else {
          await git.git(['checkout', localBranch], currentPath, 'checkoutMissingBranch', {
            processCallback: consoleProcessCallback,
          });
        }
      } else {
        this.exit(0);
        return;
      }
    }
    if (await this.missingMergeConfig4Branch(currentPath, localBranch)) {
      await git.setConfigValue(currentPath, `branch.${localBranch}.remote`, sourceUrlOrName);
      await git.setConfigValue(currentPath, `branch.${localBranch}.pushRemote`, sourceUrlOrName);
      await git.setConfigValue(currentPath, `branch.${localBranch}.merge`, ref);
    }
  }

  async missingMergeConfig4Branch(currentPath: string, branch: string) {
    const configs = await git.getConfigValue(currentPath, `branch.${branch}.merge`);
    if (!configs || !configs?.length || configs.length === 0) {
      return true;
    }
    return true;
  }

  async cmds4ExistingRemote(
    currentPath: string,
    sourceRemote: Remote,
    sourceFetchUrl: string,
    sourceBranch: string,
    flagBranch?: string,
  ) {
    const remoteBranch = `${sourceRemote.name}/${sourceBranch}`;
    const refSpec = `+refs/heads/${sourceBranch}:refs/remotes/${remoteBranch}`;
    const result = await git.fetchRefspec(currentPath, sourceFetchUrl, refSpec);
    if (result?.exitCode === 0) {
      let localBranch = sourceBranch;
      if (flagBranch) {
        localBranch = flagBranch;
      }
      const branches = await git.getBranches(currentPath);
      const branch = branches.find((b: Models.Branch) => b.name === localBranch);
      if (branch) {
        await git.git(['checkout', branch.name], currentPath, 'checkoutBranch', {
          processCallback: consoleProcessCallback,
        });
        await git.git(['merge', '--ff-only', `refs/remotes/${remoteBranch}`], currentPath, 'mergeFF', {
          processCallback: consoleProcessCallback,
        });
      } else {
        await git.git(
          ['checkout', '-b', localBranch, '--track', remoteBranch],
          currentPath,
          'checkoutBranchWithTrack',
          {
            processCallback: consoleProcessCallback,
          },
        );
      }
    }
  }
}
