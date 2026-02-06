const shell = require('shelljs');
const utils = require('../utils');

shell.exec('git tag --list --sort=taggerdate | tail -n 1', { silent: true }, function (code, stdout, stderr) {
  if (code !== 0) {
    console.log('Program stderr:', stderr);
    return;
  }
  const result = stdout.trim().split('\n');
  const tagList = Array.from(result).filter((item) => !!item);

  const [version] = tagList;
  console.log(`latest version: ${version}`);

  // 即将生成的 branch 名
  const refName = utils.isInclude(shell.env.BRANCH, utils.BRANCH_PREFIX)
    ? `${shell.env.BRANCH}`
    : utils.predictReleaseBranch(version);

  const isHotfix = utils.isEqual(shell.env.IS_HOTFIX, utils.TRUE);

  console.log(`The branch is ${refName}`);

  if (isHotfix) {
    console.log(`Notice: It's in hotfix mode`);
  }

  const { stdout: isBranchExist } = shell.exec(`${utils.validateBranchExisted(refName)}`, { silent: true });

  if (isBranchExist.trim() === utils.FALSE) {
    if (isHotfix) {
      shell.exec('echo The assigned branch in hotfix mode is required.') && shell.exit(1);
    }

    // 分支不存在时创建分支
    shell.exec(`git branch ${refName}`);
    shell.exec(`git push --set-upstream origin ${refName}`); // push 到远端
  }

  shell.exec(`git checkout ${refName}`);
});
