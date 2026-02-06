import { GitProcess } from '@tencent/code-dugite';
import * as path from 'path';
import { mkdirSync } from '../helpers/temp';
import { setupFixtureRepository } from '../helpers/repositories';
import {
  getBranchMergeConfig,
  getConfigValue,
  getGlobalBooleanConfigValue,
  getGlobalConfigPath,
  getGlobalConfigValue,
  setConfigValue,
  setGlobalConfigValue,
} from '../../src/git/config';
import { expect } from 'chai';

describe('git/config', () => {
  let repoPath: string;

  beforeEach(async () => {
    repoPath = await setupFixtureRepository('test-repo');
  });

  describe('config', () => {
    it('looks up config values', async () => {
      const bares = await getConfigValue(repoPath, 'core.bare');
      console.log(repoPath);
      expect(bares).to.not.equal(null);
      if (bares) {
        const bare = bares[0]!;
        expect(bare).to.equal('false');
      }
    });

    it('returns null for undefined values', async () => {
      const value = await getConfigValue(repoPath, 'core.the-meaning-of-lie');
      expect(value).to.equal(null);
    });
  });

  describe('global config', () => {
    const HOME = mkdirSync('global-config-here');
    const env = { HOME };
    const expectedConfigPath = path.normalize(path.join(HOME, '.gitconfig'));
    const baseArgs = ['config', '-f', expectedConfigPath];

    describe('getGlobalConfigPath', () => {
      beforeEach(async () => {
        // getGlobalConfigPath requires at least one entry, so the
        // test needs to setup an existing config value
        await GitProcess.exec([...baseArgs, 'user.name', 'bar'], __dirname);
      });

      it('gets the config path', async () => {
        const path = await getGlobalConfigPath(env);
        expect(path).to.equal(expectedConfigPath);
      });
    });

    describe('setGlobalConfigValue', () => {
      const key = 'foo.bar';

      beforeEach(async () => {
        await GitProcess.exec([...baseArgs, '--add', key, 'first'], __dirname);
        await GitProcess.exec([...baseArgs, '--add', key, 'second'], __dirname);
      });

      it('will replace all entries for a global value', async () => {
        await setGlobalConfigValue(key, 'the correct value', env);
        const values = await getGlobalConfigValue(key, env);
        expect(values).to.not.equal(null);
        if (values) {
          expect(values[0]).to.equal('the correct value');
        }
      });
    });

    describe('getGlobalBooleanConfigValue', () => {
      const key = 'foo.bar';

      it('treats "false" as false', async () => {
        await setGlobalConfigValue(key, 'false', env);
        const value = await getGlobalBooleanConfigValue(key, env);
        expect(value).to.equal(false);
      });

      it('treats "off" as false', async () => {
        await setGlobalConfigValue(key, 'off', env);
        const value = await getGlobalBooleanConfigValue(key, env);
        expect(value).to.equal(false);
      });

      it('treats "no" as false', async () => {
        await setGlobalConfigValue(key, 'no', env);
        const value = await getGlobalBooleanConfigValue(key, env);
        expect(value).to.equal(false);
      });

      it('treats "0" as false', async () => {
        await setGlobalConfigValue(key, '0', env);
        const value = await getGlobalBooleanConfigValue(key, env);
        expect(value).to.equal(false);
      });

      it('treats "true" as true', async () => {
        await setGlobalConfigValue(key, 'true', env);
        const value = await getGlobalBooleanConfigValue(key, env);
        expect(value).to.equal(true);
      });

      it('treats "yes" as true', async () => {
        await setGlobalConfigValue(key, 'yes', env);
        const value = await getGlobalBooleanConfigValue(key, env);
        expect(value).to.equal(true);
      });

      it('treats "on" as true', async () => {
        await setGlobalConfigValue(key, 'on', env);
        const value = await getGlobalBooleanConfigValue(key, env);
        expect(value).to.equal(true);
      });

      it('treats "1" as true', async () => {
        await setGlobalConfigValue(key, '1', env);
        const value = await getGlobalBooleanConfigValue(key, env);
        expect(value).to.equal(true);
      });
    });

    describe('getBranchMergeConfig', () => {
      it('returns null when no merge', async () => {
        const value = await getBranchMergeConfig(repoPath, 'master');
        expect(value).to.equal(null);
      });

      it('returns correct config value', async () => {
        await setConfigValue(repoPath, 'branch.master.remote', 'origin');
        await setConfigValue(repoPath, 'branch.master.merge', 'refs/heads/master');
        const config = await getBranchMergeConfig(repoPath, 'master');
        expect(config).to.not.equal(null);
        if (config) {
          expect(config.remoteName).to.equal('origin');
          expect(config.mergeRef).to.equal('refs/heads/master');
        }
      });
    });
  });
});
