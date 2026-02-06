import * as Path from 'path';
import { pathExists } from '../utils/path-exists';

/**
 * Check if the `.git/CHERRY_PICK_HEAD` file exists
 */
export async function isCherryPickHeadFound(repoPath: string): Promise<boolean> {
  try {
    const cherryPickHeadPath = Path.join(repoPath, '.git', 'CHERRY_PICK_HEAD');
    return pathExists(cherryPickHeadPath);
  } catch (err) {
    console.log(
      `[cherryPick] a problem was encountered reading .git/CHERRY_PICK_HEAD,
       so it is unsafe to continue cherry-picking`,
      err,
    );
    return false;
  }
}
