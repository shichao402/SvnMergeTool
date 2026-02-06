import {
  BadgeLanguage,
  GroupedReviewers,
  CertifiedReviewer,
  CertificationLevels,
  CommitCheck,
  UserSelectChoice,
  ProjectVisibilityLevel,
  MergeRequest4Detail,
} from './type';
import * as _ from 'lodash';
import { UserState, Rules, ProtectedBranch, ApiUserMixin } from '@tencent/gongfeng-cli-base/';
import { ChildProcess } from 'child_process';
import * as split2 from 'split2';
import { Badge, CertifiedReviewerType, CommitCheckState, Reviewer } from '@tencent/gongfeng-cli-base/dist/gong-feng';

export const SEPARATOR = ',';
export const MR_TEMPLATE_COMMIT_MSG = /%commit_msg%/g;

export function isNumeric(value: string) {
  return /^\d+$/.test(value);
}

export function tryPromptDoubleRoleReviewers({ ordinary, necessary }: GroupedReviewers): Required<GroupedReviewers> {
  const extractUserId = (reviewer: CertifiedReviewer) => reviewer.user.id;
  const doubleRoleUserIds = _.intersection(ordinary?.map(extractUserId) ?? [], necessary?.map(extractUserId) ?? []);
  return {
    ordinary: ordinary?.filter((reviewer) => !doubleRoleUserIds.includes(reviewer.user.id)) ?? [],
    necessary: necessary ?? [],
  };
}

export function normalizeCertifiedReviewers(
  reviewers: CertifiedReviewer[],
  invalidUserIds?: Set<number> | null,
  context: { certifiedLanguageId?: BadgeLanguage | null } = {},
) {
  const invalidIds = invalidUserIds ?? new Set();
  return reviewers.map((reviewer) => ({
    ...reviewer,
    badges: collectBadgesByLevel(reviewer.badges, null, { priorityLanguageId: context.certifiedLanguageId }),
    user: {
      ...reviewer.user,
      state: invalidIds.has(reviewer.user.id) ? UserState.INVALID : reviewer.user.state,
    },
  }));
}

export function collectBadgesByLevel(
  badgeList?: Badge[],
  requiredBadges?: Badge[] | null,
  context: { priorityLanguageId?: BadgeLanguage | null } = {},
) {
  if (!badgeList?.length) {
    return [];
  }
  const requiredLanguages = requiredBadges ? new Set(requiredBadges.map((b) => b.language)) : null;

  // iCode 不参与证书排序
  const noICode = (b: Badge) => b.level !== CertificationLevels.ICODE;
  // 不在 required badges 的证书不参与排序
  const onlyRequired = (b: Badge) => requiredLanguages?.has(b.language);
  // 先按语言字母升序进行排序，保证能展示同种语言
  const languageAscending = (b1: Badge, b2: Badge) => (b1.language > b2.language ? 1 : -1);
  // 再按证书等级进行排序，确保展示最高级的证书
  const levelDescending = (b1: Badge, b2: Badge) => b2.level - b1.level;
  // 仅收集语言的最高等级证书
  const onlyHighLevelLanguage = (grouped: Badge[], badge: Badge) =>
    grouped.some((g) => g.language === badge.language) ? grouped : [...grouped, badge];

  const results = badgeList
    .filter(noICode)
    .filter(requiredLanguages ? onlyRequired : () => true)
    .sort(languageAscending)
    .sort(levelDescending)
    .reduce(onlyHighLevelLanguage, []);

  // 根据持证搜索，优先展示当前搜索的持证信息
  if (context.priorityLanguageId) {
    return results.sort((a) => {
      if (a.languageId === context.priorityLanguageId) return -1;
      return 0;
    });
  }

  return results;
}

/**
 * 把新的评审人 newReviewers 添加到 selectedIds 缓存里
 * @param originIdCache 原始的缓存记录
 * @param newReviewers 添加到缓存的新增评审人
 */
export function refreshSelectedIdCache(originIdCache: number[], newReviewers: CertifiedReviewer[]): number[] {
  return _.uniq([...originIdCache, ...newReviewers.map((reviewer) => reviewer.user.id)]);
}

export function initializeReviewersType(list: CertifiedReviewer[] | null, targetType: CertifiedReviewerType) {
  list?.forEach((reviewer) => (reviewer.type = normalizeLegacyReviewerType(targetType, reviewer.type)));
}

/**
 * @internal
 * 历史代码只在创建页与编辑页启用了后来新增的 CertifiedReviewerType.SUGGESTION，
 * 但在详情页以及 Open API 依然保留并使用了 CertifiedReviewerType.INVITE 作为 CertifiedReviewerType.SUGGESTION，
 * 所以，如果遇到原来的类型是 INVITE，新的类型是 SUGGESTION，则应该保留原来的 INVITE，
 * 否则，可能导致移除评审人时，因对应不上添加时的 Reviewer Type 而失败
 */
function normalizeLegacyReviewerType(target: CertifiedReviewerType, origin?: CertifiedReviewerType) {
  if (!origin) return target;
  return origin === CertifiedReviewerType.INVITE && target === CertifiedReviewerType.SUGGESTION ? origin : target;
}

export function getCommitCheckerOverviewStatus(commitChecks: CommitCheck[]) {
  if (!commitChecks?.length) {
    return '';
  }
  const blockingCheckers = commitChecks?.filter(checkIfBlockingChecker) ?? [];

  // 没有 block 为 True 的检查器，则可认定为【检查通过】
  if (blockingCheckers.length === 0) {
    return CommitCheckState.SUCCESS;
  }

  return getCommitCheckerTotalStatus(blockingCheckers);
}

export function checkIfBlockingChecker(checker: CommitCheck) {
  return checker.block && checkIfBadState(checker.state);
}

function checkIfBadState(state?: CommitCheckState) {
  return state ? [CommitCheckState.FAILURE, CommitCheckState.PENDING, CommitCheckState.ERROR].includes(state) : false;
}

function getCommitCheckerTotalStatus(commitsChecks: CommitCheck[]): CommitCheckState {
  const status: any = {};
  if (!commitsChecks) {
    return CommitCheckState.SUCCESS;
  }
  commitsChecks.forEach((item: CommitCheck) => {
    switch (item.state) {
      case CommitCheckState.PENDING:
        status[CommitCheckState.PENDING] = 1;
        break;
      case CommitCheckState.ERROR:
        status[CommitCheckState.ERROR] = 1;
        break;
      case CommitCheckState.FAILURE:
        status[CommitCheckState.FAILURE] = 1;
        break;
      case CommitCheckState.SUCCESS:
        status[CommitCheckState.SUCCESS] = 1;
        break;
      default:
        break;
    }
  });
  if (!!status[CommitCheckState.ERROR]) {
    return CommitCheckState.ERROR;
  }
  if (!!status[CommitCheckState.FAILURE]) {
    return CommitCheckState.FAILURE;
  }
  if (!!status[CommitCheckState.PENDING]) {
    return CommitCheckState.PENDING;
  }
  if (!!status[CommitCheckState.SUCCESS]) {
    return CommitCheckState.SUCCESS;
  }
  return CommitCheckState.SUCCESS;
}

// Maximum length of a URL: 8192 bytes
export function validUrl(url: string) {
  return url.length < 8192;
}

/**
 * 部分评审人搜索接口使用的是用户搜索接口（autocomponent 接口），
 * 该接口返回的数据是 ApiUser 结构，需要转成专用于评审人搜索的 CertifiedReviewer 结构
 * @param users
 */
export function normalizeLegacyUsersAsReviewers(users: ApiUserMixin[] | null): CertifiedReviewer[] {
  return (
    users?.map((u) => ({
      user: u,
    })) ?? []
  );
}

export function getUserChoices(reviewers?: Reviewer[] | CertifiedReviewer[]): [UserSelectChoice[], string[]] {
  const reviewerChoices: UserSelectChoice[] = [];
  const reviewerDefault: string[] = [];
  if (reviewers?.length) {
    reviewers.forEach((r) => {
      reviewerChoices.push({
        name: r.user.username,
        value: `${r.user.id}`,
      });
      reviewerDefault.push(`${r.user.id}`);
    });
  }
  return [reviewerChoices, reviewerDefault];
}

export function isPublicProject(visibilityLevel: number) {
  return visibilityLevel === ProjectVisibilityLevel.Public;
}

export function isInternalProject(visibilityLevel: number) {
  return visibilityLevel === ProjectVisibilityLevel.Internal;
}

export function isPrivateProject(visibilityLevel: number) {
  return visibilityLevel === ProjectVisibilityLevel.Private;
}

export function isPublic(visibilityLevel: number) {
  return isPublicProject(visibilityLevel) || isInternalProject(visibilityLevel);
}

export const consoleProcessCallback = (process: ChildProcess) => {
  if (process?.stderr) {
    process.stderr.pipe(split2()).on('data', (line: string) => {
      console.log(line);
    });
  }
  if (process?.stdout) {
    process.stdout.pipe(split2()).on('data', (line: string) => {
      console.log(line);
    });
  }
};

export function isCurrentUserCanEditMr(mergeRequest4Detail: MergeRequest4Detail) {
  if (!mergeRequest4Detail.permissions.length) {
    return false;
  }
  return mergeRequest4Detail.permissions.indexOf(Rules.UPDATE_MERGE_REQUEST) >= 0 ?? false;
}

export function getDefaultDescription(config: ProtectedBranch, commitMessage = '') {
  const { mergeRequestTemplate } = config;
  if (typeof mergeRequestTemplate === 'string') {
    return mergeRequestTemplate.replace(MR_TEMPLATE_COMMIT_MSG, commitMessage);
  }
  return '';
}
