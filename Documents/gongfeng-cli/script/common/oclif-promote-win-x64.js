const shell = require('shelljs');
const { arrayFromShellOutput, BETA_FLAG } = require('../utils');

shell.exec('echo  "prepare for promote"', function () {
  const args = ['rev-parse', '--short', 'HEAD'];

  let gitSha = shell.exec(`git ${args.join(' ')}`);
  [gitSha] = arrayFromShellOutput(gitSha);

  let verison = shell.exec(`cat lerna.json | jq -r '.version'`);
  [verison] = arrayFromShellOutput(verison);

  let promoteArgs = `--version ${verison} --sha ${gitSha}`;

  if (verison.includes(BETA_FLAG)) {
    promoteArgs = promoteArgs.concat(` --channel beta`);
  }

  shell.exec(`cd packages/cli && ./bin/run promote ${promoteArgs} --targets win32-x64 --indexes`);
});
