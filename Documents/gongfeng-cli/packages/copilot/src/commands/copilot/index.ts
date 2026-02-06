import { Command } from '@oclif/core';
import { GongFengHelp } from '@tencent/gongfeng-cli-base';

export default class Copilot extends Command {
  static summary = 'AI 命令行 Copilot';
  static description = `根据自然语言描述推荐命令。
  
  还在为记住某个shell命令而苦恼吗？还在写命令时需要去网络上查询相关帮助吗？有没有想过可以直接在终端通过自然语言说出你需要什么？别担心，我们将工蜂Copilot带到了您的命令行中。工蜂Copilot for CLI可以帮您：
  - 安装和升级软件
  - 排除和调试系统问题
  - 处理和操作文件
  - 使用Git命令
  
  工蜂Copilot for CLI目前支持以下命令：
  - gf copilot sh：生成通用任意shell命令
  - gf copilot git：专用于生成Git命令，当你不需要解释您在Git的上下文中时，您的描述可以更加简洁`;
  static usage = 'copilot <command> [flags]';
  static examples = ['gf copilot sh "列出js文件"', 'gf copilot git "删除 feature 分支"'];

  async run(): Promise<void> {
    const help = new GongFengHelp(this.config);
    await help.showHelp(['copilot']);
  }
}
