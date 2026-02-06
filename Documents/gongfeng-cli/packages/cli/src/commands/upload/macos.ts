import * as _ from 'lodash';
import * as qq from 'qqjs';

import { Command, Flags, Interfaces } from '@oclif/core';

import { log } from '../../log';
import * as Tarballs from '../../tarballs';
import { templateShortKey } from '../../upload-util';
import * as path from 'path';
import mirror from '../../mirror';

export default class UploadMacos extends Command {
  static description = 'upload macos installers built with pack:macos';

  static hidden = true;

  static flags = {
    root: Flags.string({ char: 'r', description: 'path to oclif CLI root', default: '.', required: true }),
    promote: Flags.boolean({ char: 'p', description: 'promote macOS pkg' }),
    channel: Flags.string({ description: 'which channel to promote to', required: false, default: 'stable' }),
    targets: Flags.string({
      char: 't',
      description: 'comma-separated targets to upload (e.g.: darwin-x64,darwin-arm64)',
    }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(UploadMacos);
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
    const cloudPath = path.join('versions', config.version, buildConfig.gitSha);

    const cloudChannelPath = () => path.join('channels', flags.channel);

    const localFile = (filename: string) => path.join('./dist', filename);

    const upload = async (arch: Interfaces.ArchTypes) => {
      const templateKey = templateShortKey('macos', {
        bin: config.bin,
        version: config.version,
        sha: buildConfig.gitSha,
        arch,
      });
      const localPkg = dist(`macos/${templateKey}`);

      if (await qq.exists(localPkg)) {
        // await mirror.s3.deleteFile(templateKey, s3Config.host!, s3Config.folder!, cloudPath);
        await mirror.s3.uploadFile(localPkg, s3Config.host!, s3Config.folder!, cloudPath);
      } else {
        this.error('Cannot find macOS pkg', {
          suggestions: ['Run "oclif pack macos" before uploading'],
        });
      }
    };

    const arches = _.uniq(buildConfig.targets.filter((t) => t.platform === 'darwin').map((t) => t.arch));
    // eslint-disable-next-line no-await-in-loop
    for (const a of arches) await upload(a);

    log(`done uploading macos pkgs for v${config.version}-${buildConfig.gitSha}`);

    // copy darwin pkg
    if (flags.promote) {
      this.log(`Promoting macos pkgs to ${flags.channel}`);
      const arches = _.uniq(buildConfig.targets.filter((t) => t.platform === 'darwin').map((t) => t.arch));
      for (const arch of arches) {
        const darwinPkg = templateShortKey('macos', {
          bin: config.bin,
          version: config.version,
          sha: buildConfig.gitSha,
          arch,
        });
        // strip version & sha so scripts can point to a static channel pkg
        const unversionedPkg = darwinPkg.replace(`-v${config.version}-${buildConfig.gitSha}`, '');

        const unversionedPkgCopySource = localFile(unversionedPkg);
        const darwinPkgFile = path.join('./dist', 'macos', darwinPkg);
        await qq.cp(darwinPkgFile, unversionedPkgCopySource);
        const unversionedPkgChannelPath = cloudChannelPath();
        console.log(`unversionedPkgCopySource: ${unversionedPkgCopySource}`);
        console.log(`unversionedPkgChannelPath: ${unversionedPkgChannelPath}`);
        // await mirror.s3.deleteFile(unversionedPkg, s3Config.host, s3Config.folder, unversionedPkgChannelPath);
        await mirror.s3.uploadFile(unversionedPkgCopySource, s3Config.host, s3Config.folder, unversionedPkgChannelPath);
      }
    }
  }
}
