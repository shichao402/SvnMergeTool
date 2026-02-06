const shell = require('shelljs');
const utils = require('../utils');
const CLI_VERSION_KEY = 'CLI_VERSION';
const RELEASE_LABELS_KEY = 'RELEASE_LABELS';
const RELEASE_DESCRIPTION_KEY = 'RELEASE_DESCRIPTION';
const GF_INSTALLER_PREFIX = 'gongfeng-cli-v';

const X86_SUFFIX = 'x86.exe';
const X64_SUFFIX = 'x64.exe';
const PKG_FLAG = '.pkg';
const M1_PKG_SUFFIX = '-arm64.pkg';
const INTEL_PKG_SUFFIX = '-x64.pkg';

const COMMA_DIVIDER = ',';
const NEW_LINE = '<br/>';

shell.exec('echo "generate release information"', function () {
  const winsPath = `${shell.env[utils.WINS_INSTALLERS_UPLOAD_PATH]}`;
  const macPath = `${shell.env[utils.MAC_INSTALLERS_UPLOAD_PATH]}`;

  const version = `${shell.env[CLI_VERSION_KEY]}`;
  const repoLabels = [version];

  let macInstallerDescription = macPath.split(COMMA_DIVIDER);
  let winInstallerDescription = winsPath.split(COMMA_DIVIDER);

  macInstallerDescription = macInstallerDescription.map((link) => {
    // 兼容老的 oclif 发布只有 .pkg 后缀
    let displaySuffix = PKG_FLAG;

    if (utils.isInclude(link, M1_PKG_SUFFIX) || utils.isInclude(link, INTEL_PKG_SUFFIX)) {
      displaySuffix = utils.isInclude(link, M1_PKG_SUFFIX) ? M1_PKG_SUFFIX : INTEL_PKG_SUFFIX;
    }

    const installerName = `${GF_INSTALLER_PREFIX}${version}${displaySuffix}`;
    return utils.generateMarkdownLink(installerName, link);
  });

  winInstallerDescription = winInstallerDescription.map((link) => {
    const displaySuffix = utils.isInclude(link, X64_SUFFIX) ? X64_SUFFIX : X86_SUFFIX;
    const installerName = `${GF_INSTALLER_PREFIX}${version}-win-${displaySuffix}`;
    return utils.generateMarkdownLink(installerName, link);
  });

  const repoDesc = `windows:${NEW_LINE}${winInstallerDescription.join(
    NEW_LINE,
  )} ${NEW_LINE}${NEW_LINE}mac: ${NEW_LINE}${macInstallerDescription.join(NEW_LINE)} ${NEW_LINE}`;

  shell.exec(`${utils.setVariableInBK(RELEASE_DESCRIPTION_KEY, repoDesc)}`);

  // label generated
  const isHotfix = utils.isEqual(shell.env.IS_HOTFIX, utils.TRUE);
  if (isHotfix) {
    repoLabels.push('hotfix');
  }
  shell.exec(`${utils.setVariableInBK(RELEASE_LABELS_KEY, repoLabels.join(COMMA_DIVIDER))}`);
});
