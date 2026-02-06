import { getStatus } from '../../src/git/status';

/**
 * git status may return null in some edge cases but for the most
 * part we know we'll get a valid input so let's fail the test
 * if we get null, rather than need to handle it everywhere
 */
export const getStatusOrThrow = async (repoPath: string) => {
  const inner = await getStatus(repoPath);
  if (inner === null) {
    throw new Error('git status returned null which was not expected');
  }

  return inner;
};
