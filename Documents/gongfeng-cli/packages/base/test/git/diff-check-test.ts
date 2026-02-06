import {
  setupConflictedRepo,
  setupConflictedRepoWithMultipleFiles,
  setupEmptyRepository,
} from '../helpers/repositories';
import { expect } from 'chai';
import { getFilesWithConflictMarkers } from '../../src/git/diff-check';

describe('diff-check/getFilesWithConflictMarkers', () => {
  let repoPath: string;

  describe('with one conflicted file', () => {
    beforeEach(async () => {
      repoPath = await setupConflictedRepo();
    });

    it('finds one conflicted file', async () => {
      expect(await getFilesWithConflictMarkers(repoPath)).to.deep.equal(new Map([['foo', 3]]));
    });
  });

  describe('with multiple conflicted file', () => {
    beforeEach(async () => {
      repoPath = await setupConflictedRepoWithMultipleFiles();
    });

    it('finds multiple conflicted files', async () => {
      expect(await getFilesWithConflictMarkers(repoPath)).to.deep.equal(
        new Map([
          ['baz', 3],
          ['cat', 3],
          ['foo', 3],
        ]),
      );
    });
  });

  describe('with no conflicted files', () => {
    beforeEach(async () => {
      repoPath = await setupEmptyRepository();
    });

    it('finds none conflicted file', async () => {
      expect(await getFilesWithConflictMarkers(repoPath)).to.deep.equal(new Map());
    });
  });
});
