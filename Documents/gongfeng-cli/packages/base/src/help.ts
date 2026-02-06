import { Help, Command } from '@oclif/core';
import color from './color';
import { getUrlWithAdTag } from './utils/url-utility';

/**
 * 插件类型
 */
enum PluginType {
  CORE = 'core',
  USER = 'user',
}

/**
 * 各部分的标题枚举
 */
enum SectionTitle {
  USAGE = 'USAGE',
  FLAGS = 'FLAGS',
  DESCRIPTION = 'DESCRIPTION',
  EXAMPLES = 'EXAMPLES',
  COMMANDS = 'COMMANDS',
  PLUGIN_COMMANDS = 'PLUGIN COMMANDS',
  LEARN_MORE = 'LEARN MORE',
  FEEDBACK = 'FEEDBACK',
}

const DEFAULT_TOPICS_SEPARATOR = ':';
const DEFAULT_SECTIONS_SEPARATOR = '\n\n';

/**
 * 第三方插件在根级帮助中显示的翻译
 */
const thirdPartyHelpTranslationMap: Record<string, string> = {
  help: '显示命令帮助',
  update: '更新工蜂CLI',
  plugins: '工蜂CLI插件管理',
};

/**
 * 工蜂 CLI 定制 Help
 */
export default class GongFengHelp extends Help {
  /**
   * 自定义根级帮助
   */
  async showRootHelp(): Promise<void> {
    let rootCommands = this.sortedCommands;
    const state = this.config.pjson?.oclif?.state;
    if (state) {
      console.log(state === 'deprecated' ? `${this.config.bin} is deprecated` : `${this.config.bin} is in ${state}.\n`);
    }

    console.log(this.formatRoot());
    console.log('');

    if (!this.opts.all) {
      rootCommands = rootCommands.filter((c) => !c.id.includes(':'));
    }

    if (rootCommands.length > 0) {
      rootCommands = rootCommands.filter((c) => c.id);
      console.log(this.formatCommands(rootCommands));
      console.log('');
    }
    this.showLearnMore();
    this.showFeedback();
  }

  /**
   * 自定义命令帮助
   */
  async showCommandHelp(command: Command.Cached): Promise<void> {
    await super.showCommandHelp(command);
    // 仅在内置命令的help中显示 LearnMore
    if (!this.isThirdPartyPlugin(command)) {
      this.showLearnMore(command);
    }
    // 仅在根级帮助中显示 feedback
    if (!command) {
      this.showFeedback();
    }
  }

  /**
   * 自定义顶级帮助的头部
   */
  protected formatRoot(): string {
    const rootExamples = ['$ gf auth login', 'gf copilot sh "列出js文件"', '$ gf mr create', '$ gf cr create'];
    const rootDescription = this.config.pjson.oclif.description || this.config.pjson.description || '';
    const rootUsageSection = this.section(SectionTitle.USAGE, '$ gf <command> <subcommand> [flags]');
    const rootExamplesSection = this.section(
      SectionTitle.EXAMPLES,
      color.dim(rootExamples.join(DEFAULT_SECTIONS_SEPARATOR)),
    );
    return [rootDescription, rootUsageSection, rootExamplesSection].join(DEFAULT_SECTIONS_SEPARATOR);
  }

  /**
   * 自定义命令部分，将命令分为 COMMANDS 和 PLUGINS COMMANDS 两部分
   * @param commands 命令列表
   * @returns 自定义后的命令部分
   */
  protected formatCommands(commands: Command.Cached[]): string {
    if (commands.length === 0) return '';
    const commandSectionList = [];
    const coreCommands = commands.filter((command) => !this.isThirdPartyPlugin(command));
    const pluginCommands = commands.filter((command) => this.isThirdPartyPlugin(command));

    const renderCommandsBody = (commands: Command.Cached[]) => {
      if (!commands.length) return '';
      return this.renderList(
        commands.map((command) => {
          const name =
            this.config.topicSeparator !== DEFAULT_TOPICS_SEPARATOR
              ? command.id.replace(/:/g, this.config.topicSeparator)
              : command.id;
          return [name, thirdPartyHelpTranslationMap[name] || this.summary(command)];
        }),
        {
          spacer: '\n',
          stripAnsi: this.opts.stripAnsi,
          indentation: 2,
        },
      );
    };

    const coreCommandsBody = renderCommandsBody(coreCommands);
    const pluginCommandsBody = renderCommandsBody(pluginCommands);

    coreCommandsBody && commandSectionList.push(this.section(SectionTitle.COMMANDS, coreCommandsBody));
    pluginCommandsBody && commandSectionList.push(this.section(SectionTitle.PLUGIN_COMMANDS, pluginCommandsBody));

    return commandSectionList.join(DEFAULT_SECTIONS_SEPARATOR);
  }

  /**
   * 展示 LEARN MORE 部分
   * @param command 当前命令
   * @returns 返回 LEARN MORE 部分
   */
  private showLearnMore(command?: Command.Cached) {
    // 如果command没有子命令
    if (command && !this.hasSubCommands(command)) return;
    const name = command?.id || '<command>';
    const helpUrl = getUrlWithAdTag('https://git.woa.com/help/menu/solutions/CLI/introduction.html');
    const learnMoreBody = `使用“gf ${name} <subcommand> --help”获取某个命令的更多信息。
完整帮助文档：${helpUrl}`;
    const learnMoreSection = this.section(SectionTitle.LEARN_MORE, learnMoreBody);
    console.log(learnMoreSection, '\n');
    return learnMoreSection;
  }

  /**
   * 展示 FEEDBACK 部分
   * @returns 返回 FEEDBACK 部分
   */
  private showFeedback() {
    const feedbackUrl = getUrlWithAdTag('https://git.woa.com/code/code-frontend/gongfeng-cli/issues');
    const feedbackSection = this.section(SectionTitle.FEEDBACK, `有任何意见或建议欢迎提issue反馈：${feedbackUrl}`);
    console.log(feedbackSection, '\n');
    return feedbackSection;
  }

  /**
   * 检查某个命令是否有子命令
   * @param command 被检查的命令
   * @returns 返回命令是否含有子命令
   */
  private hasSubCommands(command: Command.Cached) {
    const name = command.id;
    const depth = name.split(DEFAULT_TOPICS_SEPARATOR).length;

    return (
      this.sortedCommands.filter((c) => {
        return c.id.startsWith(`${name}:`) && c.id.split(DEFAULT_TOPICS_SEPARATOR).length === depth + 1;
      }).length > 0
    );
  }

  /**
   * 判断某个命令是否为 用户使用`gf plugins add`命令安装的插件。是则返回`true`，否则返回`false`。
   * @param command 被检查的命令
   * @returns 返回是否第三方插件
   */
  private isThirdPartyPlugin(command: Command.Cached) {
    return command.pluginType !== PluginType.CORE;
  }
}
