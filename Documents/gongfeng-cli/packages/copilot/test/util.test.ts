import { expect } from '@oclif/test';
import { extractCommand } from '../src/util';

describe('test util', () => {
  it('test extract command 1', () => {
    const content =
      '```bash\n' +
      'git branch -d feature\n' +
      '```\n' +
      '\n' +
      '1. 这个命令是 `git branch` 命令的一个变体，用于删除一个已经存在的分支。\n' +
      '2. `-d` 参数表示 "delete"，意味着我们要删除指定名称的分支。在这里，`<branch_name>` 是您希望删除的分支的名称。\n' +
      '3. 当执行此命令时，Git 会检查当前工作区是否有未提交的更改。如果有，它会要求您先解决这些冲突或暂存更改，然后再继续操作。这样做是因为 Git 不允许删除已跟踪文件中的任何更改分支。\n' +
      '4. 如果 `<branch_name>` 没有被合并到其他分支并且不存在未提交的更改，那么该分支就会被安全地删除。否则，命令会显示错误信息并停止执行。\n';
    const result = extractCommand(content);

    expect(result).to.equal('git branch -d feature');
  });

  it('test extract command 2', () => {
    const content =
      '解释命令是这样的```bash\n' +
      'git branch -d feature\n' +
      '```\n' +
      '\n' +
      '1. 这个命令是 `git branch` 命令的一个变体，用于删除一个已经存在的分支。\n' +
      '2. `-d` 参数表示 "delete"，意味着我们要删除指定名称的分支。在这里，`<branch_name>` 是您希望删除的分支的名称。\n' +
      '3. 当执行此命令时，Git 会检查当前工作区是否有未提交的更改。如果有，它会要求您先解决这些冲突或暂存更改，然后再继续操作。这样做是因为 Git 不允许删除已跟踪文件中的任何更改分支。\n' +
      '4. 如果 `<branch_name>` 没有被合并到其他分支并且不存在未提交的更改，那么该分支就会被安全地删除。否则，命令会显示错误信息并停止执行。\n';
    const result = extractCommand(content);

    expect(result).to.equal('git branch -d feature');
  });

  it('test extract command 3', () => {
    const content =
      '解释命令是这样的```bash\n' +
      'git branch -d feature\n' +
      '```\n' +
      '\n' +
      '1. 这个命令是 `git branch` 命令的一个变体，用于删除一个已经存在的分支。\n' +
      '2. `-d` 参数表示 "delete"，意味着我们要删除指定名称的分支。在这里，`<branch_name>` 是您希望删除的分支的名称。\n' +
      '3. 当执行此命令时，Git 会检查当前工作区是否有未提交的更改。如果有，它会要求您先解决这些冲突或暂存更改，然后再继续操作。这样做是因为 Git 不允许删除已跟踪文件中的任何更改分支。\n' +
      '解释命令是这样的```bash\n' +
      'git branch -d feature2\n' +
      '```\n' +
      '4. 如果 `<branch_name>` 没有被合并到其他分支并且不存在未提交的更改，那么该分支就会被安全地删除。否则，命令会显示错误信息并停止执行。\n';
    const result = extractCommand(content);

    expect(result).to.equal('git branch -d feature');
  });
});
