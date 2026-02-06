import { Args, Flags } from '@oclif/core';
import BaseCommand from '../../base';
import { color } from '@tencent/gongfeng-cli-base';
import * as fs from 'fs';
import { userInfo } from 'os';
import { GenScene, GenType } from '../../type';
import { UT_BASE_PATH } from '../../const';
import * as ora from 'ora';

/**
 * aiut fix unit test
 */
export default class Fix extends BaseCommand {
  static strict = false;
  static summary = '修复单测';
  static usage = 'aiut fix <testFilePath> [-- flags...]';
  static examples = [
    '修复单个测试文件：gf aiut fix test/example_test.go',
    '修复多个测试文件：gf aiut fix test/file1_test.go,test/file2_test.go',
    '修复整个测试目录：gf aiut fix test',
  ];

  static args = {
    path: Args.string({
      required: false,
      description: '测试文件路径或测试目录路径（相对路径和绝对路径均可，多个路径使用逗号分隔）',
    }),
  };

  static flags = {
    projectPath: Flags.string({
      char: 'p',
      description: '项目路径',
      required: false,
    }),
    verbose: Flags.boolean({
      char: 'v',
      description: '是否输出详细日志',
      required: false,
    }),
  };

  async run(): Promise<void> {
    const { args, flags } = await this.parse(Fix);
    const { verbose } = flags;
    let { projectPath } = flags;
    const { path: testPath } = args;

    // 设置默认项目路径
    if (!projectPath) {
      projectPath = process.cwd();
    }

    if (!fs.existsSync(projectPath)) {
      console.log(color.error(__('pathNotExist')));
      this.exit(1);
      return;
    }

    const normalizePath = this.handleRunPath(testPath, projectPath, GenType.FILE);
    if (!normalizePath) {
      console.log(color.error('未找到有效的测试文件'));
      this.exit(1);
      return;
    }

    const projectInfo = await this.checkProject(projectPath, verbose);

    this.progressSpinner = ora().start('修复测试文件中...');

    this.utFileManager.setProjects([projectPath]);
    const watcher = this.watchUtGenProgress(GenType.FILE);

    const flagsMap: Record<string, string | string[]> = {
      '-t': 'generalAiFix',
      '-w': projectPath,
      '--user': userInfo().username,
      '--scene': GenScene.MANUAL_GEN_BY_FILE,
      '--copilotBasePath': UT_BASE_PATH,
      '--lang': projectInfo.lang || 'go',
      '--ide': 'cli',
      '--ideVersion': await this.getCliVersion(),
    };
    const runCmdArgs: string[] = [];

    const transformParams = (val: string | string[]): string => {
      if (typeof val === 'string') {
        return val;
      }
      if (typeof val === 'undefined') {
        return '';
      }
      return JSON.stringify(val);
    };
    Object.keys(flagsMap).forEach((key) => {
      if (flagsMap[key]) {
        runCmdArgs.push(key, transformParams(flagsMap[key]));
      }
    });
    runCmdArgs.push('-d', 'run', normalizePath);
    const { code } = await this.execCmd(this.utPath, runCmdArgs, {
      showLog: verbose,
      notNeedStdout: true,
    });

    if (code === 0) {
      this.progressSpinner.succeed('修复测试文件成功');
    } else {
      const errorTips = this.configService.get('errorTips');
      const tipItem = errorTips?.find((item) => item.errorCode === code);
      if (tipItem) {
        this.progressSpinner.fail(tipItem.errorMessage);
      } else {
        this.progressSpinner.fail(`修复测试文件失败, 错误码: ${code}`);
      }
    }

    await this.showGenerationResult(GenType.FILE);
    watcher.close();
    this.currentList = [];

    this.exit(code);
  }
}
