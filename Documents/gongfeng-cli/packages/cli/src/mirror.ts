import * as qq from 'qqjs';

const mirror = {
  get creds() {
    const creds = {
      token: process.env.MIRROR_TOKEN,
      username: process.env.MIRROR_USERNAME,
    };
    if (!creds.token) {
      throw new Error('Mirror token not found');
    }
    return creds;
  },
};

export default {
  get s3() {
    return {
      deleteFile: async (filename: string, host: string, folder: string, path: string) => {
        return await qq.x('curl', [
          '--request',
          'DELETE',
          '-u',
          `${mirror.creds.username}:${mirror.creds.token}`,
          '--url',
          `${host}/${folder}/${path}/${filename}`,
        ]);
      },

      uploadFile: async (local: string, host: string, folder: string, path: string) => {
        console.log(
          `curl --request PUT -u ${mirror.creds.username}:${mirror.creds.token} --url ${host}/${folder}/${path}/ --upload-file ${local}`,
        );
        return await qq.x('curl', [
          '--request',
          'PUT',
          '-u',
          `${mirror.creds.username}:${mirror.creds.token}`,
          '--url',
          `${host}/${folder}/${path}/`,
          '--upload-file',
          local,
        ]);
      },
      getJsonFile: async (file: string, host: string, folder: string, path: string) => {
        return await qq.readJSON(`${host}/${folder}/${path}/${file}`);
      },
    };
  },
};
