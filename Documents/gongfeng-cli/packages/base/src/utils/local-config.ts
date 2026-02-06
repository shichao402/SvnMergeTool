import { GitProcess } from '@tencent/code-dugite';

/**
 * 设置本机 git 配置
 * @param repoPath 项目地址
 * @param localConfig 配置信息
 */
export async function setupLocalConfig(repoPath: string, localConfig: Iterable<[string, string]>) {
  for (const [key, value] of localConfig) {
    await GitProcess.exec(['config', key, value], repoPath);
  }
}
