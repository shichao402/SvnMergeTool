import { spawn, ChildProcess, SpawnOptions } from 'child_process';

export interface CommandSucc {
  code: number;
  stdout: string;
  stderr: string;
}

export interface CommandFail extends CommandSucc {
  error?: Error;
}

export interface CommandOptions extends SpawnOptions {
  errorCb?: (result: CommandFail) => void;
  showLog?: boolean;
  notNeedStdout?: boolean;
}

export type CompletionPromise = Promise<CommandSucc>;

export interface CommandRes {
  pid: number;
  completionPromise: CompletionPromise;
}

export class CommandRunner {
  private processes: Map<number, ChildProcess> = new Map();

  private showLog = false;

  /**
   * 执行命令并实时输出日志
   * @param command 要执行的命令
   * @param args 命令的参数列表
   * @param options 命令的选项
   * @returns Promise<{code: number, stdout: string, stderr: string, error?: Error}>
   */
  public runCommand(command: string, args: string[], options: CommandOptions = {}): CommandRes {
    this.showLog = options.showLog ?? false;
    this.log('info', `Running command: ${command} ${args.join(' ')}`);
    const childProcess = spawn(command, args, options);
    const { pid } = childProcess;
    if (pid === undefined)
      return {
        pid: -1,
        completionPromise: Promise.reject({ code: -1, stdout: '', stderr: '', error: new Error('pid is undefined') }),
      };

    this.processes.set(pid, childProcess);
    let stdout = '';
    let stderr = '';

    const completionPromise = new Promise<CommandSucc>((resolve, reject) => {
      this.attachListeners(childProcess, command, args, (data, type) => {
        if (type === 'stdout') {
          // 大量日志输出的场景，防止长度超过 v8 最大字符串长度
          !options.notNeedStdout && (stdout += data);
        } else {
          stderr += data;
        }
      });

      childProcess.on('error', (error) => {
        this.log('error', `command exec error message: ${error.message}`);
        const errorRes = { code: -1, stdout, stderr, error };
        options.errorCb?.(errorRes);
        reject(errorRes);
      });

      childProcess.on('close', (code) => {
        this.processes.delete(pid);
        if (code === 0) {
          resolve({ code, stdout, stderr });
        } else {
          const errorRes = { code: code!, stdout, stderr };
          options.errorCb?.(errorRes);
          reject(errorRes);
        }
      });
    });

    return { pid, completionPromise };
  }

  /**
   * 终止子进程
   */
  public terminateCommand(pid: number): void {
    this.log('info', `Attempting to terminate command with PID: ${pid}`);
    const process = this.processes.get(pid);
    if (process && !process.killed) {
      process.kill();
      this.log('info', 'Command terminated.');
    } else {
      this.log('info', 'No active command to terminate.');
    }
  }

  public terminateAllCommands(pids: number[] = []): void {
    let allPids = pids;
    if (pids.length === 0) {
      allPids = [...this.processes.keys()];
    }
    allPids.forEach((pid) => {
      this.terminateCommand(pid);
      this.processes.delete(pid);
    });
  }

  private attachListeners(
    childProcess: ChildProcess,
    command: string,
    args: string[],
    onData: (data: string, type: 'stdout' | 'stderr') => void,
  ): void {
    let firstStdout = true;
    let firstStderr = true;
    childProcess.stdout?.on('data', (data) => {
      const message = data.toString();
      if (firstStdout) {
        this.log('info', 'command stdout:');
        firstStdout = false;
      }
      onData(message, 'stdout');
      this.log('info', message);
    });

    childProcess.stderr?.on('data', (data) => {
      const message = data.toString();
      if (firstStderr) {
        this.log('error', `Running command: ${command} ${args.join(' ')}`);
        this.log('error', 'command stderr:');
        firstStderr = false;
      }
      onData(message, 'stderr');
      this.log('error', message);
    });
  }

  private log(type: 'info' | 'error', message: string) {
    if (!this.showLog) {
      return;
    }
    console[type](message);
  }
}
