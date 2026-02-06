import { Args } from '@oclif/core';
import BaseCommand from '../../base';
import { Conversation, Message, Turn, ChatLLMClient } from '@tencent/gongfeng-llm-sdk';
import { ActionReport, authToken, color, loginUser } from '@tencent/gongfeng-cli-base';
import * as ora from 'ora';
import { CANCEL, COPY, EDIT } from '../../util';
import * as inquirer from 'inquirer';
import Debug from 'debug';
import * as clipboardy from 'clipboardy';
import { marked } from 'marked';
import * as TerminalRenderer from 'marked-terminal';

const debug = Debug('gongfeng:copilot');
enum ActionType {
  COPILOT_GIT_CANCEL = 'copilot_git_cancel',
  COPILOT_GIT_COPY = 'copilot_git_copy',
  COPILOT_GIT_EDIT = 'copilot_git_edit',
}
export default class Git extends BaseCommand {
  static summary = 'Git AI 命令行 Copilot';
  static examples = ['gf copilot git "删除feature分支"'];

  static args = {
    question: Args.string({
      required: true,
      description: '需要查询的问题',
    }),
  };

  actionReport = new ActionReport(this);
  llmClient!: ChatLLMClient;

  async run(): Promise<void> {
    const { args } = await this.parse(Git);
    const { question } = args;
    const questions: string[] = [];

    this.llmClient = new ChatLLMClient({
      host: 'https://git.woa.com/search/code_generation/api',
      endpoints: {
        streamConversation: {
          path: 'infer',
          version: 'v2',
        },
      },
      engine: 'cli',
    });

    const token = await authToken();
    const username = await loginUser();
    this.llmClient.client.interceptors.request.use((config) => {
      // config.headers.set('Authorization', `Bearer ${token}`);
      config.headers.set('X-GF-Token', token);
      config.headers.set('X-Username', username);
      return config;
    });
    await this.llmClient.initializeSession(username, {
      name: 'GongfengCLI',
      version: this.config.version,
    });

    const conversation = new Conversation();
    debug(`\ncommand conversation id: ${conversation.id}`);
    // 设置 cli 全局的系统规则
    const systemPrompt = `
    你的任务是基于用户提出的自然语言问题，仅用一行shell命令来给出答案。请确保你的回答仅包含一个git命令，不要添加任何额外的文字说明或其他内容。以下是一个示例：
    - **问题**：查看当前Git仓库的状态？
    - **回答**：git status
    
    如果用户需要对命令进行修改或进一步询问，你需要继续提供仅包含单个git命令的回答，遵循上述规则。
    任务开始了，问题：`;
    // 由于混元的问题，暂时不使用 systemPrompt，以 userPrompt 的形式代替
    // conversation.addGlobalSystemMessage(systemPrompt);

    const command = await this.unionAI(conversation, `${systemPrompt}${question}`);
    if (!command) {
      console.log(color.warn(__('noReturn')));
      this.exit(0);
      return;
    }
    questions.push(question);
    await this.loopAI(conversation, questions, command);
  }

  private async loopAI(conversation: Conversation, questions: string[], currentCommand: string) {
    console.log('');
    const answer = await inquirer.prompt({
      type: 'list',
      name: 'confirm',
      message: __('confirm'),
      choices: [
        {
          name: __('copy'),
          value: COPY,
        },
        {
          name: __('edit'),
          value: EDIT,
        },
        {
          name: __('cancel'),
          value: CANCEL,
        },
      ],
    });
    if (answer.confirm === CANCEL) {
      this.exit(0);
    }
    if (answer.confirm === EDIT) {
      const answer = await inquirer.prompt({
        type: 'input',
        name: 'question',
        message: __('enterQuestion'),
      });
      if (answer.question) {
        questions.push(answer.question);
        this.printDividing(__('queryLine'));
        let queries = '';
        questions.forEach((question, index) => {
          queries += `${index + 1}. ${question} `;
        });
        console.log(queries);
        console.log('');
        this.actionReport.report(ActionType.COPILOT_GIT_CANCEL);
        const command = await this.unionAI(conversation, `增加一个要求：${answer.question}\n请修改之前的命令。`);
        if (!command) {
          console.log(color.warn(__('noReturn')));
          this.exit(0);
          return;
        }
        await this.loopAI(conversation, questions, command);
      }
    }
    if (answer.confirm === COPY) {
      this.actionReport.report(ActionType.COPILOT_GIT_CANCEL);
      clipboardy.writeSync(currentCommand);
      console.log(color.success(__('copyCommand', { command: currentCommand })));
      this.exit(0);
    }
  }

  private async unionAI(conversation: Conversation, question: string) {
    this.printDividing(__('firstQuestionLine'));
    const spinner = ora().start(__('askAI'));
    const command = await this.askAI(conversation, question);
    if (!command) {
      return;
    }
    const markedCommand = marked(command, { renderer: new TerminalRenderer() }).trim();
    spinner.stopAndPersist({ text: markedCommand });

    this.printDividing(__('firstAnswerLine'));
    const eSpinner = ora().start(__('explaining'));
    const answer = await this.explainFromAI(command);
    const markedAnswer = marked(answer, { renderer: new TerminalRenderer() }).trim();
    eSpinner.stopAndPersist({ text: markedAnswer });
    return command;
  }

  private async askAI(conversation: Conversation, question: string) {
    // 开启一轮新的对话
    const turn = new Turn();
    debug(`\ncommand turn id: ${turn.id}`);
    // 添加用户的输入
    turn.addMessage(Message.createUserMessage(question));

    // 将新的一轮对话插入到会话中
    conversation.addTurn(turn);
    const response = await this.llmClient.streamConversation(conversation);
    const stream = response.data;
    const message = await turn.addResponse(stream);
    return message.content;
  }

  private async explainFromAI(command: string) {
    const conversation = new Conversation();
    debug(`\nexplanation conversation id: ${conversation.id}`);
    const systemPrompt =
      '作为git命令的解释大师，您的任务是向用户解释他们提出的git命令。请确保您的回答既精确又直接，避免冗长的解释，请务必保持在200字以内，另外，回答可以适当分段保持良好的可读性。现在，用户向您询问的git命令是：';
    // 由于混元的问题，暂时不使用 systemPrompt，以 userPrompt 的形式代替
    // conversation.addGlobalSystemMessage(systemPrompt);
    const turn = new Turn();
    debug(`\nexplanation turn id: ${turn.id}`);
    turn.addMessage(Message.createUserMessage(`${systemPrompt}${command}`));
    conversation.addTurn(turn);
    const response = await this.llmClient.streamConversation(conversation);
    const stream = response.data;
    const message = await turn.addResponse(stream);
    return message.content;
  }
}
