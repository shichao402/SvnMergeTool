const shell = require('shelljs');
const { arrayFromShellOutput, MIRROR_UPLOAD_SUFFIX, setVariableInBK } = require('../utils');

shell.exec('echo "generate release information"', { silent: true }, function () {
  const PROJECT_CLI_PATH = process.env.CLI_PATH;

  let repoHost = shell.exec(`cat ${PROJECT_CLI_PATH}/package.json | jq -r '.oclif.update.s3.host'`);
  [repoHost] = arrayFromShellOutput(repoHost);

  let folderPath = shell.exec(`cat ${PROJECT_CLI_PATH}/package.json | jq -r '.oclif.update.s3.folder'`);
  [folderPath] = arrayFromShellOutput(folderPath);

  let verison = shell.exec(`cat lerna.json | jq -r '.version'`);
  [verison] = arrayFromShellOutput(verison);

  const args = ['rev-parse', '--short', 'HEAD'];

  let gitSha = shell.exec(`git ${args.join(' ')}`);
  gitSha = arrayFromShellOutput(gitSha);

  // return `${repoHost}/${folderPath}/${verison}/${gitSha}/`;

  shell.exec(`${setVariableInBK(MIRROR_UPLOAD_SUFFIX, `${repoHost}/${folderPath}/versions/${verison}/${gitSha}`)}`);
});
