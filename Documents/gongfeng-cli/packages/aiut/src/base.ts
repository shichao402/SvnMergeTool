// eslint-disable-next-line @typescript-eslint/no-unused-vars
import * as typings from './types/index.d';
import axios, { AxiosInstance } from 'axios';
import { Command } from '@oclif/core';
import { checkAuth, color, CONFIG_FILE, file, getTraceId } from '@tencent/gongfeng-cli-base';
import 'reflect-metadata';
import * as i18n from 'i18n';
import * as path from 'path';
import * as Sentry from '@sentry/node';
import Debug from 'debug';
import {
  BASE_URL,
  COBUDDY_BASE_URL,
  TIMEOUT,
  UT_BASE_PATH,
  UT_FILE_NAME,
  UT_GEN_FILE_PROGRESS_PATH,
  UT_GEN_PROJECT_PROGRESS_PATH,
} from './const';
import { addExecutablePermission, download, getAuthHeader, getAllFilesFromDir, debounce, formatText } from './utils';
import { CommandFail, CommandOptions, CommandRunner } from './commandRunner';
import * as fs from 'fs';
import ApiService from './api-service';
import ConfigService from './config-service';
import { ProjectInfo, GenType, UnitTestUpdateStatus } from './type';
import { tmpdir } from 'os';
import { v4 } from 'uuid';
import * as ora from 'ora';
import { UtFileManager } from './ut-file-manager';

const debug = Debug('gongfeng-repo:base');

export default abstract class BaseCommand extends Command {
  api!: AxiosInstance;
  cobuddyApi!: AxiosInstance;
  apiService!: ApiService;
  configService!: ConfigService;
  commandRunner: CommandRunner = new CommandRunner();
  utPath = path.join(UT_BASE_PATH, UT_FILE_NAME);

  // 进度相关属性
  protected progressSpinner: ora.Ora | null = null;
  protected utFileManager: UtFileManager = new UtFileManager();
  protected currentList: any[] = [];

  async init() {
    const skip = Reflect.getMetadata('skip', this, 'run');
    if (!skip) {
      const authed = await checkAuth();
      if (!authed) {
        console.log(color.bold(color.warn('使用工蜂CLI前，请先执行"gf auth login" (别名: "gf login")登录工蜂CLI!')));
        this.exit(0);
        return;
      }
    }
    try {
      this.initI18n();
      await this.initApi();
      this.apiService = new ApiService(this.api);
      await this.cobuddyApi.post('/api/v2/auth/userinfo');
      this.configService = new ConfigService(this.apiService);
      await this.configService.fetchConfig();
      await this.downloadUt();
    } catch (e) {
      this.apiService.updateError({ message: (e as Error).message });
    }
  }

  initI18n() {
    let locale = 'zh';
    const configFile = path.join(this.config.dataDir, CONFIG_FILE);
    if (file.existsSync(configFile)) {
      const config = file.readJsonSync(configFile);
      locale = config.locale || 'zh';
    }
    let locales = path.join(__dirname, 'locales');
    if (process.env.NODE_ENV === 'development') {
      locale = 'en';
      locales = path.resolve(__dirname, '../locales');
    }
    i18n.configure({
      locales: ['en', 'zh'],
      directory: locales,
      register: global,
    });
    i18n.setLocale(locale);
  }

  async initApi() {
    this.api = axios.create({
      baseURL: BASE_URL,
      timeout: TIMEOUT,
      headers: await getAuthHeader(),
    });
    this.cobuddyApi = axios.create({
      baseURL: COBUDDY_BASE_URL,
      timeout: TIMEOUT,
      headers: await getAuthHeader(),
    });
    this.api.interceptors.response.use(
      (response) => response,
      (error) => {
        if (error.response.status === 401) {
          console.log(
            color.bold(color.warn('Api: 使用工蜂CLI前，请先执行"gf auth login" (别名: "gf login")登录工蜂CLI!')),
          );
        }
        Sentry.captureException(error);
        if (getTraceId(error)) {
          debug(`traceId: ${getTraceId(error)}`);
        }
        return Promise.reject(error);
      },
    );
  }

  async execCmd(
    command: string,
    args: string[],
    options: CommandOptions = {},
  ): Promise<{ code: number; stdout: string; stderr?: string }> {
    const newOptions = await this.getCmdOptions(options);
    const { completionPromise } = this.commandRunner.runCommand(command, args, newOptions);
    try {
      const { code, stdout } = await completionPromise;
      return { stdout, code };
    } catch (err) {
      const { code, stdout, stderr } = err as { code: number; stdout: string; stderr: string; error: Error };
      return { stdout, stderr, code };
    }
  }

  /**
   * 检测项目信息
   */
  protected async checkProject(projectPath: string, verbose?: boolean): Promise<ProjectInfo> {
    const checkCmdArgs = ['check', projectPath];
    const { stdout } = await this.execCmd(this.utPath, checkCmdArgs, {
      showLog: verbose,
    });
    let projectInfo: ProjectInfo = {};
    try {
      projectInfo = JSON.parse(stdout);
    } catch (e) {
      console.log(color.error(__('projectPathInvalid')));
      this.exit(1);
      return {};
    }
    if (!projectInfo.is_valid) {
      console.log(color.error(__('projectPathInvalid')));
      this.exit(1);
      return {};
    }
    return projectInfo;
  }

  protected async getCliVersion() {
    const { stdout } = await this.execCmd('gf', ['--version']);
    return stdout.trim();
  }

  /**
   * 处理运行路径，支持单个文件、多个文件、目录
   */
  protected handleRunPath(runPath?: string | undefined, projectPath?: string, type?: string): string {
    if (!runPath) {
      runPath = process.cwd();
    }
    if (!path.isAbsolute(runPath) && projectPath) {
      runPath = path.resolve(projectPath, runPath);
    }
    if (type === GenType.PROJECT) {
      return runPath || projectPath || '.';
    }
    if (type === GenType.FILE) {
      const pathArr = runPath.split(',');
      const allFiles = new Set<string>();
      for (let file of pathArr) {
        if (file.startsWith('.') && projectPath) {
          file = path.resolve(projectPath, file);
        }
        if (!fs.existsSync(file)) {
          continue;
        }
        if (fs.statSync(file).isDirectory()) {
          const files = getAllFilesFromDir(file);
          files.forEach((file: string) => allFiles.add(file));
        } else {
          allFiles.add(file);
        }
      }
      const content = {
        files: Array.from(allFiles),
      };
      const tempFile = path.join(tmpdir(), v4());
      fs.writeFileSync(tempFile, JSON.stringify(content));
      return tempFile;
    }
    return runPath;
  }

  /**
   * 更新生成/修复进度
   */
  protected async updateUtGenProgress(type: GenType): Promise<void> {
    const currentList = await this.utFileManager.getList(type, UnitTestUpdateStatus.CURRENT);
    const totalNum = currentList.length;
    let succeedNum = 0;
    let errorNum = 0;
    currentList.length &&
      currentList.forEach((item: any) => {
        if (item.status === UnitTestUpdateStatus.FINISH) {
          succeedNum = succeedNum + 1;
        }
        if (item.status === UnitTestUpdateStatus.ERROR) {
          errorNum = errorNum + 1;
        }
        if (!this.currentList.some((currentItem) => currentItem.id === item.id)) {
          this.currentList.push(item);
        }
      });
    if (this.progressSpinner) {
      this.progressSpinner.text = `处理中(${
        succeedNum + errorNum
      }/${totalNum}), 成功(${succeedNum} 个文件), 失败(${errorNum} 个文件)`;
    }
  }

  /**
   * 监听进度文件变化
   */
  protected watchUtGenProgress(type: GenType): fs.FSWatcher {
    const progressPath = type === GenType.PROJECT ? UT_GEN_PROJECT_PROGRESS_PATH : UT_GEN_FILE_PROGRESS_PATH;
    if (!fs.existsSync(progressPath)) {
      fs.mkdirSync(progressPath);
    }
    const debouncedUpdateUtGenProgress = debounce(() => void this.updateUtGenProgress(type), 100);
    const watcher = fs.watch(progressPath, debouncedUpdateUtGenProgress);
    return watcher;
  }

  /**
   * 显示生成/修复结果
   */
  protected async showGenerationResult(type: GenType): Promise<void> {
    try {
      const successList = await this.utFileManager.getList(type, UnitTestUpdateStatus.FINISH);
      const errorList = await this.utFileManager.getList(type, UnitTestUpdateStatus.ERROR);
      const currSuccessList = successList.filter((item) =>
        this.currentList.some((currentItem) => currentItem.id === item.id),
      );
      const currErrorList = errorList.filter((item) =>
        this.currentList.some((currentItem) => currentItem.id === item.id),
      );
      const totalCount = currSuccessList.length + currErrorList.length;

      if (totalCount === 0) {
        return;
      }

      const successRate = totalCount > 0 ? ((currSuccessList.length / totalCount) * 100).toFixed(1) : '0.0';

      // 统计信息
      console.log('📊 统计信息:');
      console.log(`   总计: ${color.info(totalCount.toString())} 个文件`);
      console.log(`   成功: ${color.success(currSuccessList.length.toString())} 个 (${successRate}%)`);
      console.log(
        `   失败: ${color.error(currErrorList.length.toString())} 个 (${(100 - parseFloat(successRate)).toFixed(1)}%)`,
      );
      console.log('');

      // 生成详细报告文件
      let detailFilePath = '';
      if (totalCount > 0) {
        detailFilePath = await this.generateDetailReport(currSuccessList, currErrorList);
      }
      const MAX_DISPLAY_COUNT = 10;
      // 成功列表
      if (currSuccessList.length > 0) {
        console.log(`✅ 处理成功 (${currSuccessList.length}):`);
        const displaySuccessList = currSuccessList.slice(0, MAX_DISPLAY_COUNT);
        displaySuccessList.forEach((item: any) => {
          console.log(`   • ${color.success(item.generated_file)}`);
        });
        if (currSuccessList.length > MAX_DISPLAY_COUNT) {
          console.log(`   ${color.dim(`... 还有 ${currSuccessList.length - MAX_DISPLAY_COUNT} 个文件`)}`);
        }
        console.log('');
      }

      // 失败列表
      if (currErrorList.length > 0) {
        console.log(`❌ 处理失败 (${currErrorList.length}):`);
        const displayErrorList = currErrorList.slice(0, MAX_DISPLAY_COUNT);
        displayErrorList.forEach((item: any) => {
          const errorMsg = formatText(item.error_msg, item.error_msg_place_holder);
          console.log(`   • ${color.error(item.generated_file)}`);
          console.log(`     错误: ${color.dim(errorMsg)}`);
        });
        if (currErrorList.length > MAX_DISPLAY_COUNT) {
          console.log(`   ${color.dim(`... 还有 ${currErrorList.length - MAX_DISPLAY_COUNT} 个文件`)}`);
        }
        console.log('');
      }

      // 显示详细报告文件路径
      if (detailFilePath) {
        console.log(`📄 完整的处理报告已保存到: ${color.info(detailFilePath)}`);
        console.log('');
      }
    } catch (error) {
      console.log(`\n${color.error('获取处理结果失败:')}`, error);
    }
  }

  /**
   * 生成详细报告
   */
  protected async generateDetailReport(successList: any[], errorList: any[]): Promise<string> {
    const reportContent = {
      timestamp: new Date().toISOString(),
      summary: {
        total: successList.length + errorList.length,
        success: successList.length,
        error: errorList.length,
        successRate:
          successList.length + errorList.length > 0
            ? `${((successList.length / (successList.length + errorList.length)) * 100).toFixed(1)}%`
            : '0.0%',
      },
      successList: successList.map((item: any) => ({
        testFile: item.generated_file,
        srcFile: item.src_file || '',
        status: 'success',
        reportPath: item.generated_report || '',
      })),
      errorList: errorList.map((item: any) => ({
        testFile: item.generated_file,
        srcFile: item.original_file || '',
        errorMsg: formatText(item.error_msg, item.error_msg_place_holder),
        status: 'error',
      })),
    };

    const reportFileName = `aiut-report-${Date.now()}.json`;
    const reportPath = path.join(tmpdir(), reportFileName);

    await fs.promises.writeFile(reportPath, JSON.stringify(reportContent, null, 2), 'utf8');

    return reportPath;
  }

  private async downloadUt() {
    const { version, url } = await this.configService.getConfig();
    const lastVersion = await this.getVersion();
    if (lastVersion && version && lastVersion === version) return;
    await download(url, UT_BASE_PATH, UT_FILE_NAME);
    await addExecutablePermission(this.utPath);
  }

  private async getVersion(): Promise<string> {
    if (!fs.existsSync(this.utPath)) return '';
    const { stdout } = await this.execCmd(this.utPath, ['-v']);
    const match = stdout.match(/version (\d+\.\d+)/);
    const version = match?.[1] || '';
    return version;
  }

  private uploadCmdErrlog({ code, stdout, stderr, error }: CommandFail) {
    const errorMessage = JSON.stringify({ stdout, stderr, error });
    this.apiService.updateError({ code, message: errorMessage });
  }

  private async getCmdOptions(options: CommandOptions = {}) {
    return {
      ...options,
      errorCb: this.uploadCmdErrlog.bind(this),
      env: {
        ...process.env,
        authHeader: JSON.stringify(await getAuthHeader()),
      },
    };
  }
}
