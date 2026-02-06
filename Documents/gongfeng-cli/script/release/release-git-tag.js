const shell = require('shelljs');
const utils = require('../utils');
const CI_FLAG = '--yes';

shell.exec('git pull', function (code, stdout, stderr) {
  if (code !== 0) {
    console.log('Program stderr:', stderr);
    return;
  }

  const isHotfix = utils.isEqual(shell.env.IS_HOTFIX, utils.TRUE);

  if (isHotfix) {
    console.log(`Notice: It's in hotfix mode`);
  }

  const { stdout: version } = shell.exec('git tag --list --sort=taggerdate | tail -n 1');

  console.log(`latest version: ${version}`);

  if (isHotfix) {
    shell.echo('hotfix 版本构建');
    shell.exec(`npx lerna publish patch --conventional-graduate --force-publish ${CI_FLAG}`);
  } else {
    shell.echo('新版本构建: ');
    shell.exec(`npx lerna publish patch --conventional-graduate --force-publish ${CI_FLAG}`);
  }
});
