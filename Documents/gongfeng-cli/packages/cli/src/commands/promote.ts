import * as path from 'path';
import * as _ from 'lodash';
import { ux, Command, Flags } from '@oclif/core';
import * as qq from 'qqjs';

import * as Tarballs from '../tarballs';
import { commitAWSDir, templateShortKey } from '../upload-util';
import { appendToIndex } from '../version-indexes';
import mirror from '../mirror';

export default class Promote extends Command {
  static description = 'promote CLI builds to a S3 release channel';

  static hidden = true;

  static flags = {
    root: Flags.string({ char: 'r', description: 'path to the oclif CLI project root', default: '.', required: true }),
    version: Flags.string({ description: 'semantic version of the CLI to promote', required: true }),
    sha: Flags.string({ description: '7-digit short git commit SHA of the CLI to promote', required: true }),
    channel: Flags.string({ description: 'which channel to promote to', required: true, default: 'stable' }),
    targets: Flags.string({ char: 't', description: 'comma-separated targets to promote (e.g.: linux-arm,win32-x64)' }),
    deb: Flags.boolean({ char: 'd', description: 'promote debian artifacts' }),
    macos: Flags.boolean({ char: 'm', description: 'promote macOS pkg' }),
    win: Flags.boolean({ char: 'w', description: 'promote Windows exe' }),
    xz: Flags.boolean({ description: 'also upload xz', allowNo: true }),
    indexes: Flags.boolean({ description: 'append the promoted urls into the index files' }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(Promote);
    const buildConfig = await Tarballs.buildConfig(flags.root, { targets: flags?.targets?.split(',') });
    const { s3Config, config } = buildConfig;
    const indexDefaults = {
      version: flags.version,
      s3Config,
    };

    if (!s3Config.folder) this.error('Cannot determine S3 folder for promotion');
    if (!s3Config.host) this.error('Cannot determine S3 host for promotion');

    const cloudBucketCommitKey = (shortKey: string) =>
      path.join(commitAWSDir(flags.version, flags.sha, s3Config), shortKey);
    const cloudChannelPath = () => path.join('channels', flags.channel);

    const localFile = (filename: string) => path.join('./dist', filename);

    // copy tarballs manifests
    if (buildConfig.targets.length > 0) this.log(`Promoting buildmanifests & unversioned tarballs to ${flags.channel}`);
    for (const target of buildConfig.targets) {
      const manifest = templateShortKey('manifest', {
        arch: target.arch,
        bin: config.bin,
        platform: target.platform,
        sha: flags.sha,
        version: flags.version,
      });
      // strip version & sha so update/scripts can point to a static channel manifest
      const unversionedManifest = manifest.replace(`-v${flags.version}-${flags.sha}`, '');
      const copySource = localFile(unversionedManifest);
      await qq.cp(localFile(manifest), copySource);
      const channelPath = cloudChannelPath();
      // await mirror.s3.deleteFile(unversionedManifest, s3Config.host, s3Config.folder, channelPath);
      await mirror.s3.uploadFile(copySource, s3Config.host, s3Config.folder, channelPath);

      const versionedTarGzName = templateShortKey('versioned', '.tar.gz', {
        arch: target.arch,
        bin: config.bin,
        platform: target.platform,
        sha: flags.sha,
        version: flags.version,
      });
      const versionedTarGzKey = cloudBucketCommitKey(versionedTarGzName);
      // strip version & sha so update/scripts can point to a static channel tarball
      const unversionedTarGzName = versionedTarGzName.replace(`-v${flags.version}-${flags.sha}`, '');
      const unversionedTarCopySource = localFile(unversionedTarGzName);
      await qq.cp(localFile(versionedTarGzName), unversionedTarCopySource);
      const unversionedTarChannelPath = cloudChannelPath();
      console.log(`unversionedTarCopySource: ${unversionedTarCopySource}`);
      console.log(`unversionedTarChannelPath: ${unversionedTarChannelPath}`);
      // await mirror.s3.deleteFile(unversionedTarGzName, s3Config.host, s3Config.folder, unversionedTarChannelPath);
      await mirror.s3.uploadFile(unversionedTarCopySource, s3Config.host, s3Config.folder, unversionedTarChannelPath);

      // eslint-disable-next-line no-await-in-loop
      if (flags.indexes)
        await appendToIndex({ ...indexDefaults, originalUrl: versionedTarGzKey, filename: unversionedTarGzName });

      if (flags.xz) {
        const versionedTarXzName = templateShortKey('versioned', '.tar.xz', {
          arch: target.arch,
          bin: config.bin,
          platform: target.platform,
          sha: flags.sha,
          version: flags.version,
        });
        const versionedTarXzKey = cloudBucketCommitKey(versionedTarXzName);
        // strip version & sha so update/scripts can point to a static channel tarball
        const unversionedTarXzName = versionedTarXzName.replace(`-v${flags.version}-${flags.sha}`, '');

        const unversionedTarXzCopySource = localFile(unversionedTarXzName);
        await qq.cp(localFile(versionedTarXzName), unversionedTarXzCopySource);
        const unversionedTarXzChannelPath = cloudChannelPath();
        console.log(`unversionedTarXzCopySource: ${unversionedTarXzCopySource}`);
        console.log(`unversionedTarXzChannelPath: ${unversionedTarXzChannelPath}`);
        // await mirror.s3.deleteFile(unversionedTarXzName, s3Config.host, s3Config.folder, unversionedTarXzChannelPath);
        await mirror.s3.uploadFile(
          unversionedTarXzCopySource,
          s3Config.host,
          s3Config.folder,
          unversionedTarXzChannelPath,
        );
        // eslint-disable-next-line no-await-in-loop
        if (flags.indexes)
          await appendToIndex({ ...indexDefaults, originalUrl: versionedTarXzKey, filename: unversionedTarXzName });
      }
    }

    // copy darwin pkg
    if (flags.macos) {
      this.log(`Promoting macos pkgs to ${flags.channel}`);
      const arches = _.uniq(buildConfig.targets.filter((t) => t.platform === 'darwin').map((t) => t.arch));
      for (const arch of arches) {
        const darwinPkg = templateShortKey('macos', { bin: config.bin, version: flags.version, sha: flags.sha, arch });
        const darwinCopySource = cloudBucketCommitKey(darwinPkg);
        // strip version & sha so scripts can point to a static channel pkg
        const unversionedPkg = darwinPkg.replace(`-v${flags.version}-${flags.sha}`, '');

        const unversionedPkgCopySource = localFile(unversionedPkg);
        const darwinPkgFile = path.join('./dist', 'macos', darwinPkg);
        await qq.cp(darwinPkgFile, unversionedPkgCopySource);
        const unversionedPkgChannelPath = cloudChannelPath();
        console.log(`unversionedPkgCopySource: ${unversionedPkgCopySource}`);
        console.log(`unversionedPkgChannelPath: ${unversionedPkgChannelPath}`);
        // await mirror.s3.deleteFile(unversionedPkg, s3Config.host, s3Config.folder, unversionedPkgChannelPath);
        await mirror.s3.uploadFile(unversionedPkgCopySource, s3Config.host, s3Config.folder, unversionedPkgChannelPath);
        if (flags.indexes)
          await appendToIndex({ ...indexDefaults, originalUrl: darwinCopySource, filename: unversionedPkg });
      }
    }

    // copy win exe
    if (flags.win) {
      this.log(`Promoting windows exe to ${flags.channel}`);
      const archs = buildConfig.targets.filter((t) => t.platform === 'win32').map((t) => t.arch);
      for (const arch of archs) {
        const winPkg = templateShortKey('win32', { bin: config.bin, version: flags.version, sha: flags.sha, arch });
        const winCopySource = cloudBucketCommitKey(winPkg);
        // strip version & sha so scripts can point to a static channel exe
        const unversionedExe = winPkg.replace(`-v${flags.version}-${flags.sha}`, '');

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
        if (flags.indexes)
          await appendToIndex({ ...indexDefaults, originalUrl: winCopySource, filename: unversionedExe });
        ux.action.stop('successfully');
      }
    }
  }
}
