import { Command, Flags, Interfaces } from '@oclif/core';
import * as qq from 'qqjs';

import { log } from '../../log';
import * as Tarballs from '../../tarballs';
import { templateShortKey } from '../../upload-util';
import * as path from 'path';
import mirror from '../../mirror';

export default class UploadTarballs extends Command {
  static description = 'upload an oclif CLI to mirror.';

  static hidden = true;

  static flags = {
    root: Flags.string({ char: 'r', description: 'path to oclif CLI root', default: '.', required: true }),
    targets: Flags.string({ char: 't', description: 'comma-separated targets to upload (e.g.: linux-arm,win32-x64)' }),
    xz: Flags.boolean({ description: 'also upload xz', allowNo: true }),
  };

  async run(): Promise<void> {
    const { flags } = await this.parse(UploadTarballs);
    if (process.platform === 'win32') throw new Error('upload does not function on windows');
    const buildConfig = await Tarballs.buildConfig(flags.root, { xz: flags.xz, targets: flags?.targets?.split(',') });
    const { s3Config, dist, config, xz } = buildConfig;

    if (!s3Config.host) {
      this.error('Cannot determine S3 host for upload');
      return;
    }
    if (!s3Config.folder) {
      this.error('Cannot determine S3 folder for upload');
      return;
    }

    // fail early if targets are not built
    for (const target of buildConfig.targets) {
      const tarball = dist(
        templateShortKey('versioned', {
          ext: '.tar.gz',
          bin: config.bin,
          version: config.version,
          sha: buildConfig.gitSha,
          ...target,
        }),
      );
      // eslint-disable-next-line no-await-in-loop
      if (!(await qq.exists(tarball)))
        this.error(`Cannot find a tarball ${tarball} for ${target.platform}-${target.arch}`, {
          suggestions: [`Run "oclif pack --target ${target.platform}-${target.arch}" before uploading`],
        });
    }

    const uploadTarball = async (options?: { platform: Interfaces.PlatformTypes; arch: Interfaces.ArchTypes }) => {
      const releaseTarballs = async (ext: '.tar.gz' | '.tar.xz') => {
        const localKey = templateShortKey('versioned', ext, {
          // eslint-disable-next-line @typescript-eslint/no-non-null-asserted-optional-chain
          arch: options?.arch!,
          bin: config.bin,
          // eslint-disable-next-line @typescript-eslint/no-non-null-asserted-optional-chain
          platform: options?.platform!,
          sha: buildConfig.gitSha,
          version: config.version,
        });

        const cloudPath = path.join('versions', config.version, buildConfig.gitSha);
        // await mirror.s3.deleteFile(localKey, s3Config.host!, s3Config.folder!, cloudPath);
        await mirror.s3.uploadFile(dist(localKey), s3Config.host!, s3Config.folder!, cloudPath);
      };

      await releaseTarballs('.tar.gz');
      if (xz) await releaseTarballs('.tar.xz');

      const manifest = templateShortKey('manifest', {
        // eslint-disable-next-line @typescript-eslint/no-non-null-asserted-optional-chain
        arch: options?.arch!,
        bin: config.bin,
        // eslint-disable-next-line @typescript-eslint/no-non-null-asserted-optional-chain
        platform: options?.platform!,
        sha: buildConfig.gitSha,
        version: config.version,
      });
      const manifestCloudPath = path.join('versions', config.version, buildConfig.gitSha);
      // await mirror.s3.deleteFile(manifest, s3Config.host!, s3Config.folder!, manifestCloudPath);
      await mirror.s3.uploadFile(dist(manifest), s3Config.host!, s3Config.folder!, manifestCloudPath);
    };

    if (buildConfig.targets.length > 0) log('uploading targets');
    // eslint-disable-next-line no-await-in-loop
    for (const target of buildConfig.targets) await uploadTarball(target);
    log(`done uploading tarballs & manifests for v${config.version}-${buildConfig.gitSha}`);
  }
}
