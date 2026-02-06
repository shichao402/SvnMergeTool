const shell = require('shelljs');
const { MIRROR_UPLOAD_SUFFIX, arrayFromShellOutput, setVariableInBK, MAC_INSTALLERS_UPLOAD_PATH } = require('../utils');

shell.exec('echo  "generate release information for mac installers"', function () {
  const PROJECT_CLI_PATH = process.env.CLI_PATH;

  const installer = shell.exec(`cd ${PROJECT_CLI_PATH}/dist/macos && ls`);
  const files = arrayFromShellOutput(installer);

  const uploadSuffix = process.env[MIRROR_UPLOAD_SUFFIX];

  const uploadFilesList = files.map((file) => {
    return `${uploadSuffix}/${file}`;
  });

  shell.exec(setVariableInBK(MAC_INSTALLERS_UPLOAD_PATH, uploadFilesList.join(',')));
});
