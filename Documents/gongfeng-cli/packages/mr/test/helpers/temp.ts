/* eslint-disable no-sync */

/** Module for creating and managing temporary directories and files, using the
 * `temp` Node module
 */
import * as temp from 'temp';
import { promisify } from 'util';
const tempTrack = temp.track();

/**
 * Open a new temporary directory, specifying the prefix/suffix options the
 * directory should use
 */
export const mkdirSync = tempTrack.mkdirSync;
/**
 * Open a new temporary file, specifying the prefix/suffix options the file
 * should use
 */
export const openSync = tempTrack.openSync;

export const createTempDirectory = promisify(tempTrack.mkdir.bind(tempTrack));
