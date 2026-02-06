import * as fs from 'fs-extra';
import * as path from 'path';
import { BuildConfig } from './tarballs';
import { debug as Debug } from './log';
import mirror from './mirror';

const debug = Debug.new('version-indexes');

interface VersionsObject {
  [key: string]: string;
}

const sortVersionsObjectByKeysDesc = (input: VersionsObject, keyLimit?: number): VersionsObject => {
  const keys = (Reflect.ownKeys(input).sort((a, b) => {
    const splitA = (a as string).split('.').map((part) => Number.parseInt(part, 10));
    const splitB = (b as string).split('.').map((part) => Number.parseInt(part, 10));
    // sort by major
    if (splitA[0] < splitB[0]) return 1;
    if (splitA[0] > splitB[0]) return -1;
    // sort by minor
    if (splitA[1] < splitB[1]) return 1;
    if (splitA[1] > splitB[1]) return -1;
    // sort by patch
    if (splitA[2] < splitB[2]) return 1;
    if (splitA[2] > splitB[2]) return -1;
    return 0;
  }) as string[]).slice(0, keyLimit); // undefined keyLimit returns the entire array
  const result: VersionsObject = {};
  for (const key of keys) {
    result[key] = input[key];
  }

  return result;
};

// appends to an existing file (or writes a new one) with the versions in descending order, with an optional limit from the pjson file
export const appendToIndex = async (input: {
  version: string;
  originalUrl: string;
  filename: string;
  s3Config: BuildConfig['s3Config'];
}): Promise<void> => {
  const { version, originalUrl, filename, s3Config } = input;
  // these checks are both nice for users AND helpful for TS
  if (!s3Config.folder) throw new Error('[package.json].oclif.s3.folder is required for indexes');
  if (!s3Config.host) throw new Error('[package.json].oclif.s3.host is required for indexes');

  // json-friendly filenames like sfdx-linux-x64-tar-gz
  const jsonFileName = `${filename.replace(/\./g, '-')}.json`;
  const key = path.join(s3Config.folder!, 'versions', jsonFileName);

  // retrieve existing index file
  let existing = {};
  try {
    existing = await mirror.s3.getJsonFile(jsonFileName, s3Config.host, s3Config.folder, 'versions');
    debug('appending to existing index file');
  } catch (error: any) {
    // console.log(error);
    debug(`error on ${key}`, error);
  }

  // appends new version from this promotion if not already present (idempotent)
  await fs.writeJSON(
    jsonFileName,
    sortVersionsObjectByKeysDesc(
      {
        ...existing,
        [version]: `${s3Config.host}/${originalUrl}`,
      },
      s3Config.indexVersionLimit,
    ),
    { spaces: 2 },
  );

  // put the file back in the same place
  // await mirror.s3.deleteFile(jsonFileName, s3Config.host, s3Config.folder, 'versions');
  await mirror.s3.uploadFile(jsonFileName, s3Config.host, s3Config.folder, 'versions');
  // cleans up local fs
  await fs.remove(jsonFileName);
};
