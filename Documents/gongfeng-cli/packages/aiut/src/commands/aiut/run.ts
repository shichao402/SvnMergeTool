import { Args, Flags } from '@oclif/core';
import BaseCommand from '../../base';
import { GenScene, GenType, ReferenceType } from '../../type';
import { color } from '@tencent/gongfeng-cli-base';
import * as fs from 'fs';
import { userInfo } from 'os';
import { UT_BASE_PATH } from '../../const';
import * as inquirer from 'inquirer';
import * as path from 'path';
import * as ora from 'ora';
import { ConfigItem } from '../../config-service';

/**
 * aiut generate unit test
 */
export default class Run extends BaseCommand {
  static strict = false;
  static summary = '生成单测';
  static usage = 'aiut run <projectPath> [-- flags...]';
  static examples = [
    '项目生成：gf aiut run . --type project --projectPath projectPath',
    '文件/文件夹生成：gf aiut run filePath,folderPath --type file --projectPath projectPath',
  ];

  static args = {
    path: Args.string({
      required: false,
      description:
        '项目生成传项目路径，文件/文件夹生成传文件/文件夹路径（相对路径和绝对路径均可，多个路径使用逗号分隔）',
    }),
  };

  static flags = {
    type: Flags.string({
      char: 't',
      description: '生成类型（项目生成：project, 文件/文件夹生成：file）',
      required: false,
      default: GenType.PROJECT,
    }),
    projectPath: Flags.string({
      char: 'p',
      description: '项目路径',
      required: false,
    }),
    model: Flags.string({
      char: 'm',
      description: '模型名称',
      required: false,
    }),
    framework: Flags.string({
      char: 'f',
      description: '框架名称',
      required: false,
    }),
    ignoreRule: Flags.string({
      char: 'i',
      description: '忽略规则(glob语法, 多个用逗号分隔)',
      required: false,
    }),
    verbose: Flags.boolean({
      char: 'v',
      description: '是否输出详细日志',
      required: false,
    }),
    default: Flags.boolean({
      char: 'd',
      description: '是否使用默认值',
      required: false,
    }),
    referenceType: Flags.string({
      char: 'r',
      description: '参考类型',
      required: false,
    }),
    referencePath: Flags.string({
      char: 'e',
      description: '指定文件路径',
      required: false,
    }),
    langConfig: Flags.string({
      description: '语言配置(JSON字符串)',
      required: false,
    }),
  };

  async run(): Promise<void> {
    const { args, flags } = await this.parse(Run);
    const { verbose, type } = flags;
    let { model, framework, ignoreRule, referenceType, referencePath, projectPath } = flags;
    const { langConfig: langConfigFlag } = flags;
    const { path: runPath } = args;
    if (!projectPath) {
      projectPath = process.cwd();
    }
    const normalizePath = this.handleRunPath(runPath, projectPath, type);
    if (fs.existsSync(projectPath) === false || fs.existsSync(normalizePath) === false) {
      console.log(color.error(__('pathNotExist')));
      this.exit(1);
      return;
    }
    const projectInfo = await this.checkProject(projectPath, verbose);
    const scene = type === GenType.FILE ? GenScene.MANUAL_GEN_BY_FILE : GenScene.MANUAL_GEN_BY_PROJECT;
    const models = this.configService.getModels(projectInfo.lang!, scene);
    const frameworks = this.configService.getFrameworks(projectInfo.lang!);
    const defaultLanguage = this.configService.get('defaultLanguage');
    const defaultFramework = this.configService.get('defaultFramework');
    const errorTips = this.configService.get('errorTips');
    const langConfig = this.configService.get('langConfig') || {};
    const currLangConfig = langConfig[projectInfo.lang!] || [];
    if (flags.default !== true) {
      if (!model) {
        const modelChoices = models.map((model) => ({
          name: model.label,
          value: model.value,
        }));
        const modelAnswer = await inquirer.prompt({
          type: 'list',
          name: 'model',
          message: __('selectModel'),
          choices: modelChoices,
        });
        model = modelAnswer.model;
      }
      if (!referenceType) {
        const referenceTypeAnswer = await inquirer.prompt({
          type: 'list',
          name: 'referenceType',
          message: __('selectReferenceType'),
          choices: [
            { name: '上下文（自动学习已有单测风格，寻找同目录下相近测试用例进行学习）', value: ReferenceType.CONTEXT },
            { name: '指定文件（选择单测文件，参考其风格生成单测）', value: ReferenceType.FILE },
            { name: '官方推荐（按官方推荐的框架和风格生成单测）', value: ReferenceType.OFFICIAL },
          ],
        });
        referenceType = referenceTypeAnswer.referenceType;
        if (referenceType === ReferenceType.FILE) {
          const referencePathAnswer = await inquirer.prompt({
            type: 'input',
            name: 'referencePath',
            message: __('inputReferencePath'),
          });
          referencePath = referencePathAnswer.referencePath;
        }
        if (referenceType === ReferenceType.OFFICIAL) {
          const frameworkChoices = frameworks.map((framework) => ({
            name: framework.label,
            value: framework.value,
          }));
          const frameworkAnswer = await inquirer.prompt({
            type: 'list',
            name: 'framework',
            message: __('selectFramework'),
            choices: frameworkChoices,
          });
          framework = frameworkAnswer.framework;
        }
      }
      if (!ignoreRule) {
        const ignoreRuleAnswer = await inquirer.prompt({
          type: 'input',
          name: 'ignoreRule',
          message: __('inputIgnoreRule'),
          filter: (input: string) =>
            input
              .split(',')
              .map((item) => item.trim())
              .filter(Boolean),
        });
        ignoreRule = ignoreRuleAnswer.ignoreRule;
      }
    }

    let parsedLangConfig: Record<string, any> = {};
    try {
      if (langConfigFlag) {
        parsedLangConfig = JSON.parse(langConfigFlag);
      }
    } catch (error) {
      // ignore
    }

    const dynamicFlags: Record<string, any> = {};
    for (const config of currLangConfig as ConfigItem[]) {
      const { key, type: configType, label, options, defaultValue, required } = config;
      let value = (flags as any)[key] || parsedLangConfig[key];
      if (flags.default) {
        value = value || defaultValue;
      }
      if (value === undefined && flags.default !== true) {
        if (configType === 'select') {
          const answer = await inquirer.prompt({
            type: 'list',
            name: key,
            message: `请选择${label}`,
            choices: options.map((opt) => ({ name: opt.label, value: opt.value })),
            default: defaultValue,
          });
          value = answer[key];
        } else if (configType === 'input') {
          const answer = await inquirer.prompt({
            type: 'input',
            name: key,
            message: `请输入${label}`,
            default: defaultValue,
            validate: (input) => {
              if (required && !input) {
                return '此项为必填项';
              }
              return true;
            },
          });
          value = answer[key];
        }
      }
      if (value !== undefined) {
        dynamicFlags[key] = value;
      }
    }

    // 将用户选择后的完整命令打印出来
    const commandParts = ['gf', 'aiut', 'run'];

    // 添加位置参数
    if (runPath) {
      commandParts.push(runPath);
    }

    // 添加标志参数
    const originFlagsMap = {
      '--type': type,
      '--projectPath': projectPath,
      '--model': model,
      '--framework': framework,
      '--ignoreRule': Array.isArray(ignoreRule) ? ignoreRule.join(',') : ignoreRule,
      '--referenceType': referenceType,
      '--referencePath': referencePath,
      '--verbose': verbose,
      '--default': flags.default,
      '--langConfig': Object.keys(dynamicFlags).length > 0 ? JSON.stringify(dynamicFlags) : undefined,
    };

    Object.entries(originFlagsMap).forEach(([flag, value]) => {
      if (value !== undefined && value !== '') {
        // 布尔值标志不需要值
        const flagStr = value === true ? flag : `${flag}=${value}`;
        commandParts.push(flagStr);
      }
    });

    const fullCommand = commandParts.join(' ');
    console.log('完整命令:', color.info(fullCommand));

    this.progressSpinner = ora().start(__('genProjectUnitTest'));
    let runCmdArgs: string[] = [];
    const cmdTypeMap: Record<GenScene, string> = {
      [GenScene.MANUAL_GEN_BY_FILE]: 'batch',
      [GenScene.MANUAL_GEN_BY_PROJECT]: 'project',
    };
    const flagsMap: Record<string, string | string[] | boolean> = {
      '-t': cmdTypeMap[scene],
      '-w': projectPath,
      '--autoStop': true,
      '--user': userInfo().username,
      '--scene': scene,
      '--copilotBasePath': UT_BASE_PATH,
      '--lang': projectInfo.lang || defaultLanguage || 'go',
      '--model': model || models[0]?.value,
      '--globConfig': ignoreRule || '',
      '--ide': 'cli',
      '--ideVersion': await this.getCliVersion(),
      '--referenceType': referenceType || ReferenceType.CONTEXT,
    };
    if (Object.keys(dynamicFlags).length > 0) {
      flagsMap['--langConfig'] = JSON.stringify(dynamicFlags);
    }
    if (referenceType === ReferenceType.FILE && referencePath) {
      const referencePathArray = referencePath.split(',').map((pathStr) => {
        const trimmedPath = pathStr.trim();
        if (!path.isAbsolute(trimmedPath) && projectPath) {
          return path.resolve(projectPath, trimmedPath);
        }
        return trimmedPath;
      });
      flagsMap['--referenceFile'] = referencePathArray;
    }
    if (referenceType === ReferenceType.OFFICIAL) {
      flagsMap['--utFramework'] = framework || defaultFramework || 'gotest';
    }
    const transformParams = (val: string | string[] | boolean): string => {
      if (typeof val === 'string') {
        return val;
      }
      if (typeof val === 'undefined' || typeof val === 'boolean') {
        return '';
      }
      return JSON.stringify(val);
    };
    Object.keys(flagsMap).forEach((key) => {
      if (flagsMap[key]) {
        runCmdArgs.push(key, transformParams(flagsMap[key]));
      }
    });
    runCmdArgs = runCmdArgs.filter(Boolean);
    runCmdArgs.push('-d', 'run', type === GenType.FILE ? normalizePath : '.');
    this.utFileManager.setProjects([projectPath]);
    const watcher = this.watchUtGenProgress(type as GenType);
    const { code } = await this.execCmd(this.utPath, runCmdArgs, {
      showLog: verbose,
      notNeedStdout: true,
    });
    if (code === 0) {
      this.progressSpinner.succeed(__('genProjectUnitTestSuccess'));
    } else {
      const tipItem = errorTips?.find((item) => item.errorCode === code);
      if (tipItem) {
        this.progressSpinner.fail(tipItem.errorMessage);
      } else {
        this.progressSpinner.fail(__('genProjectUnitTestFailed'));
      }
    }
    // 显示详细的生成结果
    await this.showGenerationResult(type as GenType);
    watcher.close();
    this.currentList = [];
    this.exit(code);
  }
}
