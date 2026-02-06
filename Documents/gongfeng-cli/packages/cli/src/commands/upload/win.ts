import { Command, Flags, Interfaces } from '@oclif/core';
import * as qq from 'qqjs';

import { log } from '../../log';
import * as Tarballs from '../../tarballs';
import { templateShortKey } from '../../upload-util';
import * as path from 'path';
import mirror from '../../mirror';

export default class UploadWin extends Command {
  static description = 'upload windows installers built with pack:win';

  static hidden = true;

  static flags = {
    root: Flags.string({ char: 'r', description: 'path to oclif CLI root', default: '.', required: true }),
    promote: Flags.boolean({ char: 'p', description: 'promote win exe' }),
    channel: Flags.string({ description: 'which channel to promote to', required: false, default: 'stable' }),
    targets: Flags.string({
      char: 't',
      description: 'comma-separated targets to upload (e.g.: darwin-x64,darwin-arm64)',
    }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(UploadWin);
    const buildConfig = await Tarballs.buildConfig(flags.root, { targets: flags?.targets?.split(',') });
    const { s3Config, config, dist } = buildConfig;

    if (!s3Config.host) {
      this.error('Cannot determine S3 host for upload');
      return;
    }
    if (!s3Config.folder) {
      this.error('Cannot determine S3 folder for upload');
      return;
    }

    const archs = buildConfig.targets.filter((t) => t.platform === 'win32').map((t) => t.arch);

    for (const arch of archs) {
      const templateKey = templateShortKey('win32', {
        bin: config.bin,
        version: config.version,
        sha: buildConfig.gitSha,
        arch,
      });
      const localKey = dist(`win32/${templateKey}`);
      // eslint-disable-next-line no-await-in-loop
      if (!(await qq.exists(localKey)))
        this.error(`Cannot find Windows exe for ${arch}`, {
          suggestions: ['Run "oclif pack win" before uploading'],
        });
    }

    const cloudPath = path.join('versions', config.version, buildConfig.gitSha);

    const cloudChannelPath = () => path.join('channels', flags.channel);
    const localFile = (filename: string) => path.join('./dist', filename);

    const uploadWin = async (arch: Interfaces.ArchTypes) => {
      const templateKey = templateShortKey('win32', {
        bin: config.bin,
        version: config.version,
        sha: buildConfig.gitSha,
        arch,
      });
      const localExe = dist(`win32/${templateKey}`);
      if (await qq.exists(localExe)) {
        // await mirror.s3.deleteFile(templateKey, s3Config.host!, s3Config.folder!, cloudPath);
        await mirror.s3.uploadFile(localExe, s3Config.host!, s3Config.folder!, cloudPath);
      }
    };

    for (const arch of archs) {
      await uploadWin(arch);
    }

    log(`done uploading windows executables for v${config.version}-${buildConfig.gitSha}`);

    if (flags.promote) {
      this.log(`Promoting windows exe to ${flags.channel}`);
      const archs = buildConfig.targets.filter((t) => t.platform === 'win32').map((t) => t.arch);
      for (const arch of archs) {
        const winPkg = templateShortKey('win32', {
          bin: config.bin,
          version: config.version,
          sha: buildConfig.gitSha,
          arch,
        });
        // strip version & sha so scripts can point to a static channel exe
        const unversionedExe = winPkg.replace(`-v${config.version}-${buildConfig.gitSha}`, '');

        const unversionedWinPkgCopySource = localFile(unversionedExe);
        const winPkgFile = path.join('./dist', 'win32', winPkg);
        await qq.cp(winPkgFile, unversionedWinPkgCopySource);
        const unversionedWinPkgChannelPath = cloudChannelPath();
        console.log(`unversionedPkgCopySource: ${unversionedWinPkgCopySource}`);
        console.log(`unversionedWinPkgChannelPath: ${unversionedWinPkgChannelPath}`);
        // await mirror.s3.deleteFile(unversionedExe, s3Config.host, s3Config.folder, unversionedWinPkgChannelPath);
        await mirror.s3.uploadFile(
          unversionedWinPkgCopySource,
          s3Config.host,
          s3Config.folder,
          unversionedWinPkgChannelPath,
        );
      }
    }
  }
}
