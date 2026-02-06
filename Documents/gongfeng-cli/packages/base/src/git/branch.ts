import { getRefSha } from './refs';
import { TrackingRef } from '../models';
import { getRemotes } from './remote';
import { getBranchMergeConfig } from './config';

async function getRefs(refsForLookup: string[], repoPath: string) {
  const refs = [];
  for (const ref of refsForLookup) {
    const refHash = await getRefSha(repoPath, ref);
    if (refHash) {
      const splits = refHash.split(' ');
      if (splits.length < 2) {
        continue;
      }
      const [hash, name] = splits;
      refs.push({
        hash,
        name,
      });
    }
  }
  return refs;
}

export async function determineTrackingBranch(repoPath: string, branch: string): Promise<TrackingRef | null> {
  const remotes = await getRemotes(repoPath);
  if (!remotes.length) {
    return null;
  }
  const refsForLookup = ['HEAD'];
  const trackingRefs: TrackingRef[] = [];

  const config = await getBranchMergeConfig(repoPath, branch);
  if (config?.remoteName) {
    const tr: TrackingRef = {
      remoteName: config.remoteName,
      branchName: config.mergeRef?.replace(/^refs\/heads\//, '') ?? '',
    };
    trackingRefs.push(tr);
    refsForLookup.push(trackingRefToString(tr));
  }

  const refs = await getRefs(refsForLookup, repoPath);
  if (refs.length > 1) {
    const sliceRefs = refs.slice(1);
    for (let i = 0; i < sliceRefs.length; i++) {
      const ref = sliceRefs[i];
      if (ref.hash !== refs[0].hash) {
        continue;
      }
      for (let j = 0; i < trackingRefs.length; j++) {
        const tr = trackingRefs[j];
        if (trackingRefToString(tr) !== ref.name) {
          continue;
        }
        return tr;
      }
    }
  }
  return null;
}

function trackingRefToString(tr: TrackingRef) {
  return `refs/remotes/${tr.remoteName}/${tr.branchName}`;
}
