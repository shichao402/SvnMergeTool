const shell = require('shelljs');
const { BETA_FLAG, isEqual, TRUE } = require('../utils');
const CI_FLAG = '--yes';
const VERSION_DIVIDER = '.';

const REVIEW_NUM = 10;

shell.exec(
  `git tag --list --sort=-taggerdate | head -n ${REVIEW_NUM} `,
  { silent: true },
  function (code, stdout, stderr) {
    if (code !== 0) {
      console.log('Program stderr:', stderr);
      return;
    }

    const forceNewVersion = isEqual(shell.env.FORCE_UPDATE, TRUE);

    // 强制更新新版本
    if (forceNewVersion) {
      shell.echo('Notice: 强制构建新版本!!');
      shell.exec(`npx lerna publish preminor --preid beta --conventional-prerelease --force-publish ${CI_FLAG}`);
      return;
    }

    const result = String(stdout).split('\n');
    const tagList = Array.from(result).filter((item) => !!item);

    const [latestVersion, secondVersion] = tagList;

    console.log(`最新的版本 version: ${latestVersion}`);
    console.log(`倒数第二个版本 version: ${secondVersion}`);

    if (!latestVersion.includes(BETA_FLAG)) {
      // 当上一个版本没有带 beta 位
      const latestMinorVersion = latestVersion.split(VERSION_DIVIDER).slice(0, 2).join(VERSION_DIVIDER);
      const secondMinorVersion = secondVersion.split(VERSION_DIVIDER).slice(0, 2).join(VERSION_DIVIDER);
      if (latestMinorVersion === secondMinorVersion) {
        console.log(`用于匹配的两个版本号：${latestMinorVersion} && ${secondMinorVersion}`);
        // 最新的版本和倒数第二个版本的 minor 相同，说明是刚刚 release 的版本，需要升 minor 位，带上 beta，否则可能为 hotfix 之前的版本的构建，暂不升级
        shell.echo('新版本构建: ');
        shell.exec(`npx lerna publish preminor --preid beta --conventional-prerelease ${CI_FLAG}`);
        return;
      }
    }
    shell.echo('普通版本构建: ');
    shell.exec(`npx lerna publish prepatch --preid beta --conventional-prerelease ${CI_FLAG}`);
  },
);
