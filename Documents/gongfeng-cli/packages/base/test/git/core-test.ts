import { setupFixtureRepository } from '../helpers/repositories';
import { git } from '../../src/git/core';
import { GitError } from '@tencent/code-dugite';
import { expect } from 'chai';

describe('git/core', () => {
  let repositoryPath: string;
  beforeEach(async () => {
    repositoryPath = await setupFixtureRepository('test-repo');
  });

  describe('error handling', () => {
    it('does not throw for errors that were expected', async () => {
      const args = ['rev-list', '--left-right', '--count', 'some-ref', '--'];
      let threw = false;
      try {
        const result = await git(args, repositoryPath, 'test', {
          expectedErrors: new Set([GitError.BadRevision]),
        });
        expect(result.gitError).to.equal(GitError.BadRevision);
      } catch (e) {
        threw = true;
      }

      expect(threw).to.equal(false);
    });

    it('throws for errors that were not expected', async () => {
      const args = ['rev-list', '--left-right', '--count', 'some-ref', '--'];
      let threw = false;
      try {
        await git(args, repositoryPath, 'test', {
          expectedErrors: new Set([GitError.SSHKeyAuditUnverified]),
        });
      } catch (e) {
        threw = true;
      }
      expect(threw).to.equal(true);
    });
  });

  describe('exit code handling', () => {
    it('does not throw for exit codes that were expected', async () => {
      const args = ['rev-list', '--left-right', '--count', 'some-ref', '--'];
      let threw = false;
      try {
        const result = await git(args, repositoryPath, 'test', {
          successExitCodes: new Set([128]),
        });
        expect(result.exitCode).to.equal(128);
      } catch (e) {
        threw = true;
      }
      expect(threw).to.equal(false);
    });

    it('throws for exit codes that were not expected', async () => {
      const args = ['rev-list', '--left-right', '--count', 'some-ref', '--'];
      let threw = false;
      try {
        await git(args, repositoryPath, 'test', {
          successExitCodes: new Set([2]),
        });
      } catch (e) {
        threw = true;
      }
      expect(threw).to.equal(true);
    });
  });
});
