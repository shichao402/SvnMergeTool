const BETA_FLAG = '-beta';
const BRANCH_PREFIX = 'release-';
const FALSE = 'false';
const TRUE = 'true';
const MIRROR_UPLOAD_SUFFIX = 'MIRROR_UPLOAD_SUFFIX';
const MAC_INSTALLERS_UPLOAD_PATH = 'MAC_INSTALLERS_UPLOAD_PATH';
const WINS_INSTALLERS_UPLOAD_PATH = 'WINS_INSTALLERS_UPLOAD_PATH';

// 判断 git 远端中该分支是否存在
const validateBranchExisted = function (refName) {
  return `if git rev-parse --verify ${refName}; then
          echo 'true'; else echo '${FALSE}'; fi`;
};

// 推测当前的 release 分支名应该是什么
const predictReleaseBranch = function (version) {
  const stableVersion = version.split(BETA_FLAG)[0];
  const release = stableVersion.replace(/.\d*$/, '').slice(1);
  return `${BRANCH_PREFIX}${release}`;
};

// 由于流水线基本为文本输出，所以判断需要改为这种形式
const isEqual = function (shellOutput, expected) {
  return `${shellOutput}`.trim() === expected;
};

// 判断当前文本中是否带有相关的文案，string.includes 的效果
const isInclude = function (shellOutput, expected) {
  return `${shellOutput}`.trim().includes(expected);
};

// 生成链接格式的 markdown
const generateMarkdownLink = function (fileName, link) {
  return `[${fileName}](${link})`;
};

// 将流水线返回的带换行格式的长文本改为数组形式输出
const arrayFromShellOutput = function (shellOutput = '') {
  return shellOutput.trim().split('\n');
};

// 根据蓝盾流水线要求，设置蓝盾的流水线 step 变量 echo 格式
const setVariableInBK = function (key, value) {
  return ` echo "::set-variable name=${key}::${value}"`;
};

module.exports = {
  BETA_FLAG,
  BRANCH_PREFIX,
  FALSE,
  TRUE,
  validateBranchExisted,
  predictReleaseBranch,
  isEqual,
  isInclude,
  generateMarkdownLink,
  arrayFromShellOutput,
  setVariableInBK,
  MIRROR_UPLOAD_SUFFIX,
  WINS_INSTALLERS_UPLOAD_PATH,
  MAC_INSTALLERS_UPLOAD_PATH,
};
