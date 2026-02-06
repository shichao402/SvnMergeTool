import { expect, test } from '@oclif/test';
import * as base from '@tencent/gongfeng-cli-base';
import { setupEmptyDirectory, setupFixtureRepository } from '../../helpers/repositories';
import { git } from '@tencent/gongfeng-cli-base';

const { file } = base;

describe('mr show', () => {
  describe('check login', () => {
    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return false;
        };
      })
      .stdout()
      .command(['mr show', '1'])
      .exit(0)
      .it('exit when not authed', ({ stdout }) => {
        expect(stdout).to.contain('使用工蜂CLI前，请先执行"gf auth login" (别名:  "gf login")登录工蜂CLI!');
      });
  });

  describe('with non git directory', () => {
    let repoPath: string;
    beforeEach(() => {
      repoPath = setupEmptyDirectory();
    });
    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return true;
        };
      })
      .stub(file, 'readJsonSync', () => {
        return {};
      })
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .stdout()
      .command(['mr show', '1'])
      .exit(0)
      .it('exit when remote not found', (ctx) => {
        expect(ctx.stdout).to.contain('Current project remote not found!');
      });
  });

  describe('show merge request', () => {
    let repoPath: string;
    beforeEach(async () => {
      repoPath = await setupFixtureRepository('test-repo');
      await git.addRemote(repoPath, 'origin', 'https://git.woa.com/code/cli');
    });
    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return true;
        };
      })
      .stub(file, 'readJsonSync', () => {
        return {};
      })
      .stub(base.vars, 'host', () => {
        return 'git.woa.com';
      })
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .nock('https://git.woa.com', (api) => {
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, undefined);
      })
      .stdout()
      .command(['mr show', '1'])
      .exit(0)
      .it('exit when project not found', (ctx) => {
        expect(ctx.stdout).to.contain('Project not found on GongFeng');
      });

    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return true;
        };
      })
      .stub(file, 'readJsonSync', () => {
        return {};
      })
      .stub(base.vars, 'host', () => {
        return 'git.woa.com';
      })
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .nock('https://git.woa.com', (api) => {
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 1000 });
        api.get('/api/web/v1/projects/1000/merge_requests/1').reply(200, undefined);
      })
      .stdout()
      .command(['mr show', '1'])
      .exit(0)
      .it('exit when merge request not found', (ctx) => {
        expect(ctx.stdout).to.contain('Merge request !1 not found!');
      });

    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return true;
        };
      })
      .stub(file, 'readJsonSync', () => {
        return {};
      })
      .stub(base.vars, 'host', () => {
        return 'git.woa.com';
      })
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .nock('https://git.woa.com', (api) => {
        api.get('/api/web/v1/projects/code%2Fcli').reply(200, { id: 10712436 });
        api.get('/api/web/v1/projects/10712436/merge_requests/1').reply(200, {
          mergeRequest: {
            authorId: 70664,
            assigneeId: 70664,
            milestoneId: 2938,
            targetProjectId: 10712436,
            targetBranch: 'master',
            sourceProjectId: 10712436,
            sourceBranch: 'dev',
            state: 'opened',
            mergeStatus: 'cannot_be_merged',
            commitCheckState: null,
            commitCheckBlock: null,
            iid: 1,
            position: 0,
            lockedAt: null,
            updatedById: 70664,
            createdAt: 1658373949000,
            updatedAt: 1659336631000,
            resolvedAt: null,
            allowBroken: false,
            lastCommitId: null,
            latestMergeRequestDiffId: 2455025,
            mergeType: null,
            mergeCommitSha: null,
            rebaseCommitSha: null,
            prePushMR: false,
            assignee: {
              id: 70664,
              avatar: 'thumb_200-2-899-898_14b82f2d40b54bfbafc9db4499be3724.jpeg',
              name: '我有一个很长长长长长长长长长长长长长长的名字',
              username: 'rhainliu',
              state: 'active',
              blocked: false,
            },
            author: {
              id: 70664,
              avatar: 'thumb_200-2-899-898_14b82f2d40b54bfbafc9db4499be3724.jpeg',
              name: '我有一个很长长长长长长长长长长长长长长的名字',
              username: 'rhainliu',
              state: 'active',
              blocked: false,
            },
            review: null,
            titleRaw: '更新文件 README.md',
            descriptionRaw: 'Update 9813.md ',
          },
          milestone: {
            title: 'qeqwe',
            state: 'active',
            iid: 1,
            dueDate: 1659312000000,
            createdAt: 1659320767000,
            description: 'eqw',
          },
          commitChecks: [],
          labels: [
            {
              id: 138083,
              title: 'wewe',
              color: '#428bca',
              sourceType: 'Project',
              sourceId: 10712436,
              template: false,
              createdAt: 1659320729000,
              updatedAt: 1659320729000,
            },
            {
              id: 138084,
              title: 'rrrr',
              color: '#428bca',
              sourceType: 'Project',
              sourceId: 10712436,
              template: false,
              createdAt: 1659320735000,
              updatedAt: 1659320735000,
            },
          ],
          targetProject: {
            pushResetEnabled: true,
            suggestionReviewer: null,
            necessaryReviewer: null,
            approverRule: 1,
            necessaryApproverRule: 0,
            canApproveByCreator: false,
            autoCreateReviewAfterPush: false,
            autoCreateReviewPrePush: false,
            forbiddenModifyRule: false,
            mergeRequestTemplate: '%commit_msg%',
            pathReviewerRules: null,
            fileOwnerPathRules: null,
            defaultBranch: 'master',
            allowMergeCommits: true,
            allowSquashMerging: true,
            allowRebaseMerging: true,
            defaultMergeMethod: 0,
            forceAddLabelsInNote: false,
            mergeManager: null,
            mergeRequestMustLinkTapdTickets: false,
            allowCertifiedApproverEnabled: false,
            certifiedApproverRule: 1,
            certificateLevel: 1,
            certifiedLanguageRule: null,
            ownersReviewEnabled: false,
            initialOwnersMinCount: 1,
            id: 10712436,
            name: 'cli',
            path: 'cli',
            fullPath: 'rhainliu/cli',
            fullName: 'rhainliu/cli',
            group: {
              id: 3031,
              name: 'rhainliu',
              path: 'rhainliu',
              type: null,
              avatar: null,
            },
            repositorySize: 0.001,
            groupFullPath: 'rhainliu',
            simplePath: 'rhainliu/cli',
            groupFullName: 'rhainliu',
          },
          sourceProject: {
            pushResetEnabled: true,
            suggestionReviewer: null,
            necessaryReviewer: null,
            approverRule: 1,
            necessaryApproverRule: 0,
            canApproveByCreator: false,
            autoCreateReviewAfterPush: false,
            autoCreateReviewPrePush: false,
            forbiddenModifyRule: false,
            mergeRequestTemplate: '%commit_msg%',
            pathReviewerRules: null,
            fileOwnerPathRules: null,
            defaultBranch: 'master',
            allowMergeCommits: true,
            allowSquashMerging: true,
            allowRebaseMerging: true,
            defaultMergeMethod: 0,
            forceAddLabelsInNote: false,
            mergeManager: null,
            mergeRequestMustLinkTapdTickets: false,
            allowCertifiedApproverEnabled: false,
            certifiedApproverRule: 1,
            certificateLevel: 1,
            certifiedLanguageRule: null,
            ownersReviewEnabled: false,
            initialOwnersMinCount: 1,
            id: 10712436,
            name: 'cli',
            path: 'cli',
            fullPath: 'rhainliu/cli',
            fullName: 'rhainliu/cli',
            group: {
              id: 3031,
              name: 'rhainliu',
              path: 'rhainliu',
              type: null,
              avatar: null,
            },
            repositorySize: 0.001,
            groupFullPath: 'rhainliu',
            simplePath: 'rhainliu/cli',
            groupFullName: 'rhainliu',
          },
          review: {
            id: 77752,
            projectId: 10712436,
            iid: 1,
            authorId: 70664,
            reviewableId: 1594157,
            reviewableType: 'merge_request',
            commitId: null,
            state: 'approving',
            fileReviewState: 'empty',
            restrictType: null,
            approverRule: 1,
            necessaryApproverRule: 0,
            pushResetEnabled: true,
            createdAt: 1658373949000,
            updatedAt: 1658373949000,
            noteUnresolvedTotal: 0,
            allowCertifiedApproverEnabled: false,
            resolvedCheck: false,
            ownersReviewEnabled: false,
            initialOwnersMinCount: 1,
            author: {
              id: 70664,
              avatar: 'thumb_200-2-899-898_14b82f2d40b54bfbafc9db4499be3724.jpeg',
              name: '我有一个很长长长长长长长长长长长长长长的名字',
              username: 'rhainliu',
              state: 'active',
              blocked: false,
            },
            reviewCertifiedBadges: null,
          },
        });
        api.get('/api/web/v1/projects/10712436/reviews/1/config').reply(200, {
          normalReviewers: [
            {
              id: 10005279,
              reviewId: 77752,
              userId: 265952,
              projectId: 10712436,
              type: 'invite',
              state: 'approving',
              updatedAt: 1659353736000,
              user: {
                id: 265952,
                avatar: null,
                name: 'lyndahuang',
                username: 'lyndahuang',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: [
                {
                  id: 2,
                  languageId: 1,
                  name: 'iRead',
                  language: 'C++',
                  shortName: 'iRead',
                  shortLanguage: 'C++',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
              ],
            },
            {
              id: 10005280,
              reviewId: 77752,
              userId: 202775,
              projectId: 10712436,
              type: 'invite',
              state: 'approving',
              updatedAt: 1659353736000,
              user: {
                id: 202775,
                avatar: null,
                name: 'v_xinphou',
                username: 'v_xinphou',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: [
                {
                  id: 4,
                  languageId: 3,
                  name: 'iRead',
                  language: 'Java',
                  shortName: 'iRead',
                  shortLanguage: 'Java',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 2,
                  languageId: 1,
                  name: 'iRead',
                  language: 'C++',
                  shortName: 'iRead',
                  shortLanguage: 'C++',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
              ],
            },
          ],
          necessaryReviewers: [
            {
              id: 10005272,
              reviewId: 77752,
              userId: 228615,
              projectId: 10712436,
              type: 'necessary',
              state: 'approving',
              updatedAt: 1659346321000,
              user: {
                id: 228615,
                avatar: 'thumb_17-0-221-221_fae281c123c04c8ba5b48b68629d171c.png',
                name: 'devxhxh',
                username: 'v_ytingsu',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: [
                {
                  id: 4,
                  languageId: 3,
                  name: 'iRead',
                  language: 'Java',
                  shortName: 'iRead',
                  shortLanguage: 'Java',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 3,
                  languageId: 2,
                  name: 'iRead',
                  language: 'Go',
                  shortName: 'iRead',
                  shortLanguage: 'Go',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 21,
                  languageId: 2,
                  name: 'iMaster',
                  language: 'Go',
                  shortName: 'iMaster',
                  shortLanguage: 'Go',
                  description: 'approver_description',
                  icon: 'approver_go_icon',
                  level: 4,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 22,
                  languageId: 3,
                  name: 'iMaster',
                  language: 'Java',
                  shortName: 'iMaster',
                  shortLanguage: 'Java',
                  description: 'approver_description',
                  icon: 'approver_java_icon',
                  level: 4,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 6,
                  languageId: 5,
                  name: 'iRead',
                  language: 'Objective-C',
                  shortName: 'iRead',
                  shortLanguage: 'OC',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 2,
                  languageId: 1,
                  name: 'iRead',
                  language: 'C++',
                  shortName: 'iRead',
                  shortLanguage: 'C++',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 5,
                  languageId: 4,
                  name: 'iRead',
                  language: 'JavaScript/TypeScript',
                  shortName: 'iRead',
                  shortLanguage: 'JS/TS',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
              ],
            },
            {
              id: 10005273,
              reviewId: 77752,
              userId: 265934,
              projectId: 10712436,
              type: 'necessary',
              state: 'approving',
              updatedAt: 1659346321000,
              user: {
                id: 265934,
                avatar: 'thumb_0-0-400-400_66fee4b2f8dd4b1fbe3003fff4df454b.jpeg',
                name: 'dev/cs工蜂dev/cs工蜂dev/cs工蜂dev/cs工蜂dev/cs工蜂dev/cs工蜂dev/cs工蜂',
                username: 'cszhouzhou',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: null,
            },
            {
              id: 10005274,
              reviewId: 77752,
              userId: 265898,
              projectId: 10712436,
              type: 'necessary',
              state: 'approving',
              updatedAt: 1659346321000,
              user: {
                id: 265898,
                avatar: null,
                name: 'shayleehu',
                username: 'shayleehu',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: [
                {
                  id: 7,
                  languageId: 6,
                  name: 'iRead',
                  language: 'Python',
                  shortName: 'iRead',
                  shortLanguage: 'Python',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 2,
                  languageId: 1,
                  name: 'iRead',
                  language: 'C++',
                  shortName: 'iRead',
                  shortLanguage: 'C++',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 4,
                  languageId: 3,
                  name: 'iRead',
                  language: 'Java',
                  shortName: 'iRead',
                  shortLanguage: 'Java',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 6,
                  languageId: 5,
                  name: 'iRead',
                  language: 'Objective-C',
                  shortName: 'iRead',
                  shortLanguage: 'OC',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 3,
                  languageId: 2,
                  name: 'iRead',
                  language: 'Go',
                  shortName: 'iRead',
                  shortLanguage: 'Go',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 5,
                  languageId: 4,
                  name: 'iRead',
                  language: 'JavaScript/TypeScript',
                  shortName: 'iRead',
                  shortLanguage: 'JS/TS',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
              ],
            },
          ],
          certifiedReviewers: [],
          validBadges: [],
          author: {
            id: null,
            reviewId: null,
            userId: null,
            projectId: null,
            type: null,
            state: null,
            updatedAt: null,
            user: {
              id: 70664,
              avatar: 'thumb_200-2-899-898_14b82f2d40b54bfbafc9db4499be3724.jpeg',
              name: '我有一个很长长长长长长长长长长长长长长的名字',
              username: 'rhainliu',
              state: 'active',
              blocked: false,
            },
            duration: null,
            badges: [],
          },
          invalidUsers: [],
        });
        api.get('/api/web/v1/projects/10712436/cc/users?ccType=MergeRequest&iid=1').reply(200, [
          { id: 202775, avatar: null, name: 'v_xinphou', username: 'v_xinphou', state: 'active' },
          { id: 265898, avatar: null, name: 'shayleehu', username: 'shayleehu', state: 'active' },
        ]);
        api.get('/api/web/v1/projects/10712436/reviews/1/tapds').reply(200, [
          {
            id: '6092',
            workspaceId: 10114641,
            sourceProjectId: 10712436,
            sourceId: 1,
            sourceType: 'mr',
            tapdId: '1010114641854938893',
            tapdType: 'story',
            name: 'Update 9813.md',
            status: 'planning',
            statusZh: '规划中',
          },
          {
            id: '6093',
            workspaceId: 20357985,
            sourceProjectId: 10712436,
            sourceId: 1,
            sourceType: 'mr',
            tapdId: '1020357985854929165',
            tapdType: 'story',
            name: 'ceshi  squash',
            status: 'planning',
            statusZh: '规划中',
          },
        ]);
      })
      .stdout()
      .command(['mr show', '1'])
      .it('current project merge request exist', (ctx) => {
        expect(ctx.stdout).to.contain('更新文件 README.md');
        expect(ctx.stdout).to.contain('dev -> master');
        expect(ctx.stdout).to.contain('Author: rhainliu');
        expect(ctx.stdout).to.contain('Labels:  wewe, rrrr');
        expect(ctx.stdout).to.contain('Milestone: qeqwe');
        expect(ctx.stdout).to.contain('Review state: Approving');
        expect(ctx.stdout).to.contain(
          'Reviewers: v_ytingsu[V] [iMaster-Go] [iMaster-Java] [iRead-C++] [iRead-JS/TS] [iRead-OC](Approving)',
        );
        expect(ctx.stdout).to.contain('【Story】: Update 9813.md');
        expect(ctx.stdout).to.contain('Carbon Copy: v_xinphou,shayleehu');
      });

    test
      .stub(base, 'checkAuth', () => {
        return () => {
          return true;
        };
      })
      .stub(file, 'readJsonSync', () => {
        return {};
      })
      .stub(base.vars, 'host', () => {
        return 'git.woa.com';
      })
      .stub(process, 'cwd', () => {
        return repoPath;
      })
      .nock('https://git.woa.com', (api) => {
        api.get('/api/web/v1/projects/gongfeng%2Fcli').reply(200, { id: 10712436 });
        api.get('/api/web/v1/projects/10712436/merge_requests/1').reply(200, {
          mergeRequest: {
            authorId: 70664,
            assigneeId: 70664,
            milestoneId: 2938,
            targetProjectId: 10712436,
            targetBranch: 'master',
            sourceProjectId: 10712436,
            sourceBranch: 'dev',
            state: 'opened',
            mergeStatus: 'cannot_be_merged',
            commitCheckState: null,
            commitCheckBlock: null,
            iid: 1,
            position: 0,
            lockedAt: null,
            updatedById: 70664,
            createdAt: 1658373949000,
            updatedAt: 1659336631000,
            resolvedAt: null,
            allowBroken: false,
            lastCommitId: null,
            latestMergeRequestDiffId: 2455025,
            mergeType: null,
            mergeCommitSha: null,
            rebaseCommitSha: null,
            prePushMR: false,
            assignee: {
              id: 70664,
              avatar: 'thumb_200-2-899-898_14b82f2d40b54bfbafc9db4499be3724.jpeg',
              name: '我有一个很长长长长长长长长长长长长长长的名字',
              username: 'rhainliu',
              state: 'active',
              blocked: false,
            },
            author: {
              id: 70664,
              avatar: 'thumb_200-2-899-898_14b82f2d40b54bfbafc9db4499be3724.jpeg',
              name: '我有一个很长长长长长长长长长长长长长长的名字',
              username: 'rhainliu',
              state: 'active',
              blocked: false,
            },
            review: null,
            titleRaw: '更新文件 README.md',
            descriptionRaw: 'Update 9813.md',
          },
          milestone: {
            title: 'qeqwe',
            state: 'active',
            iid: 1,
            dueDate: 1659312000000,
            createdAt: 1659320767000,
            description: 'eqw',
          },
          commitChecks: [],
          labels: [
            {
              id: 138083,
              title: 'wewe',
              color: '#428bca',
              sourceType: 'Project',
              sourceId: 10712436,
              template: false,
              createdAt: 1659320729000,
              updatedAt: 1659320729000,
            },
            {
              id: 138084,
              title: 'rrrr',
              color: '#428bca',
              sourceType: 'Project',
              sourceId: 10712436,
              template: false,
              createdAt: 1659320735000,
              updatedAt: 1659320735000,
            },
          ],
          targetProject: {
            pushResetEnabled: true,
            suggestionReviewer: null,
            necessaryReviewer: null,
            approverRule: 1,
            necessaryApproverRule: 0,
            canApproveByCreator: false,
            autoCreateReviewAfterPush: false,
            autoCreateReviewPrePush: false,
            forbiddenModifyRule: false,
            mergeRequestTemplate: '%commit_msg%',
            pathReviewerRules: null,
            fileOwnerPathRules: null,
            defaultBranch: 'master',
            allowMergeCommits: true,
            allowSquashMerging: true,
            allowRebaseMerging: true,
            defaultMergeMethod: 0,
            forceAddLabelsInNote: false,
            mergeManager: null,
            mergeRequestMustLinkTapdTickets: false,
            allowCertifiedApproverEnabled: false,
            certifiedApproverRule: 1,
            certificateLevel: 1,
            certifiedLanguageRule: null,
            ownersReviewEnabled: false,
            initialOwnersMinCount: 1,
            id: 10712436,
            name: 'cli',
            path: 'cli',
            fullPath: 'rhainliu/cli',
            fullName: 'rhainliu/cli',
            group: {
              id: 3031,
              name: 'rhainliu',
              path: 'rhainliu',
              type: null,
              avatar: null,
            },
            repositorySize: 0.001,
            groupFullPath: 'rhainliu',
            simplePath: 'rhainliu/cli',
            groupFullName: 'rhainliu',
          },
          sourceProject: {
            pushResetEnabled: true,
            suggestionReviewer: null,
            necessaryReviewer: null,
            approverRule: 1,
            necessaryApproverRule: 0,
            canApproveByCreator: false,
            autoCreateReviewAfterPush: false,
            autoCreateReviewPrePush: false,
            forbiddenModifyRule: false,
            mergeRequestTemplate: '%commit_msg%',
            pathReviewerRules: null,
            fileOwnerPathRules: null,
            defaultBranch: 'master',
            allowMergeCommits: true,
            allowSquashMerging: true,
            allowRebaseMerging: true,
            defaultMergeMethod: 0,
            forceAddLabelsInNote: false,
            mergeManager: null,
            mergeRequestMustLinkTapdTickets: false,
            allowCertifiedApproverEnabled: false,
            certifiedApproverRule: 1,
            certificateLevel: 1,
            certifiedLanguageRule: null,
            ownersReviewEnabled: false,
            initialOwnersMinCount: 1,
            id: 10712436,
            name: 'cli',
            path: 'cli',
            fullPath: 'rhainliu/cli',
            fullName: 'rhainliu/cli',
            group: {
              id: 3031,
              name: 'rhainliu',
              path: 'rhainliu',
              type: null,
              avatar: null,
            },
            repositorySize: 0.001,
            groupFullPath: 'rhainliu',
            simplePath: 'rhainliu/cli',
            groupFullName: 'rhainliu',
          },
          review: {
            id: 77752,
            projectId: 10712436,
            iid: 1,
            authorId: 70664,
            reviewableId: 1594157,
            reviewableType: 'merge_request',
            commitId: null,
            state: 'approving',
            fileReviewState: 'empty',
            restrictType: null,
            approverRule: 1,
            necessaryApproverRule: 0,
            pushResetEnabled: true,
            createdAt: 1658373949000,
            updatedAt: 1658373949000,
            noteUnresolvedTotal: 0,
            allowCertifiedApproverEnabled: false,
            resolvedCheck: false,
            ownersReviewEnabled: false,
            initialOwnersMinCount: 1,
            author: {
              id: 70664,
              avatar: 'thumb_200-2-899-898_14b82f2d40b54bfbafc9db4499be3724.jpeg',
              name: '我有一个很长长长长长长长长长长长长长长的名字',
              username: 'rhainliu',
              state: 'active',
              blocked: false,
            },
            reviewCertifiedBadges: null,
          },
        });
        api.get('/api/web/v1/projects/10712436/reviews/1/config').reply(200, {
          normalReviewers: [
            {
              id: 10005279,
              reviewId: 77752,
              userId: 265952,
              projectId: 10712436,
              type: 'invite',
              state: 'approving',
              updatedAt: 1659353736000,
              user: {
                id: 265952,
                avatar: null,
                name: 'lyndahuang',
                username: 'lyndahuang',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: [
                {
                  id: 2,
                  languageId: 1,
                  name: 'iRead',
                  language: 'C++',
                  shortName: 'iRead',
                  shortLanguage: 'C++',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
              ],
            },
            {
              id: 10005280,
              reviewId: 77752,
              userId: 202775,
              projectId: 10712436,
              type: 'invite',
              state: 'approving',
              updatedAt: 1659353736000,
              user: {
                id: 202775,
                avatar: null,
                name: 'v_xinphou',
                username: 'v_xinphou',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: [
                {
                  id: 4,
                  languageId: 3,
                  name: 'iRead',
                  language: 'Java',
                  shortName: 'iRead',
                  shortLanguage: 'Java',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 2,
                  languageId: 1,
                  name: 'iRead',
                  language: 'C++',
                  shortName: 'iRead',
                  shortLanguage: 'C++',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
              ],
            },
          ],
          necessaryReviewers: [
            {
              id: 10005272,
              reviewId: 77752,
              userId: 228615,
              projectId: 10712436,
              type: 'necessary',
              state: 'approving',
              updatedAt: 1659346321000,
              user: {
                id: 228615,
                avatar: 'thumb_17-0-221-221_fae281c123c04c8ba5b48b68629d171c.png',
                name: 'devxhxh',
                username: 'v_ytingsu',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: [
                {
                  id: 4,
                  languageId: 3,
                  name: 'iRead',
                  language: 'Java',
                  shortName: 'iRead',
                  shortLanguage: 'Java',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 3,
                  languageId: 2,
                  name: 'iRead',
                  language: 'Go',
                  shortName: 'iRead',
                  shortLanguage: 'Go',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 21,
                  languageId: 2,
                  name: 'iMaster',
                  language: 'Go',
                  shortName: 'iMaster',
                  shortLanguage: 'Go',
                  description: 'approver_description',
                  icon: 'approver_go_icon',
                  level: 4,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 22,
                  languageId: 3,
                  name: 'iMaster',
                  language: 'Java',
                  shortName: 'iMaster',
                  shortLanguage: 'Java',
                  description: 'approver_description',
                  icon: 'approver_java_icon',
                  level: 4,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 6,
                  languageId: 5,
                  name: 'iRead',
                  language: 'Objective-C',
                  shortName: 'iRead',
                  shortLanguage: 'OC',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 2,
                  languageId: 1,
                  name: 'iRead',
                  language: 'C++',
                  shortName: 'iRead',
                  shortLanguage: 'C++',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 5,
                  languageId: 4,
                  name: 'iRead',
                  language: 'JavaScript/TypeScript',
                  shortName: 'iRead',
                  shortLanguage: 'JS/TS',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
              ],
            },
            {
              id: 10005273,
              reviewId: 77752,
              userId: 265934,
              projectId: 10712436,
              type: 'necessary',
              state: 'approving',
              updatedAt: 1659346321000,
              user: {
                id: 265934,
                avatar: 'thumb_0-0-400-400_66fee4b2f8dd4b1fbe3003fff4df454b.jpeg',
                name: 'dev/cs工蜂dev/cs工蜂dev/cs工蜂dev/cs工蜂dev/cs工蜂dev/cs工蜂dev/cs工蜂',
                username: 'cszhouzhou',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: null,
            },
            {
              id: 10005274,
              reviewId: 77752,
              userId: 265898,
              projectId: 10712436,
              type: 'necessary',
              state: 'approving',
              updatedAt: 1659346321000,
              user: {
                id: 265898,
                avatar: null,
                name: 'shayleehu',
                username: 'shayleehu',
                state: 'active',
                blocked: false,
              },
              duration: null,
              badges: [
                {
                  id: 7,
                  languageId: 6,
                  name: 'iRead',
                  language: 'Python',
                  shortName: 'iRead',
                  shortLanguage: 'Python',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 2,
                  languageId: 1,
                  name: 'iRead',
                  language: 'C++',
                  shortName: 'iRead',
                  shortLanguage: 'C++',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 4,
                  languageId: 3,
                  name: 'iRead',
                  language: 'Java',
                  shortName: 'iRead',
                  shortLanguage: 'Java',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 6,
                  languageId: 5,
                  name: 'iRead',
                  language: 'Objective-C',
                  shortName: 'iRead',
                  shortLanguage: 'OC',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 3,
                  languageId: 2,
                  name: 'iRead',
                  language: 'Go',
                  shortName: 'iRead',
                  shortLanguage: 'Go',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
                {
                  id: 5,
                  languageId: 4,
                  name: 'iRead',
                  language: 'JavaScript/TypeScript',
                  shortName: 'iRead',
                  shortLanguage: 'JS/TS',
                  description: 'readability_foundation_description',
                  icon: 'readability_foundation_icon',
                  level: 1,
                  type: 'review',
                  createdAt: '2021-10-12T12:00:00+0000',
                  updatedAt: '2021-10-12T12:00:00+0000',
                },
              ],
            },
          ],
          certifiedReviewers: [],
          validBadges: [],
          author: {
            id: null,
            reviewId: null,
            userId: null,
            projectId: null,
            type: null,
            state: null,
            updatedAt: null,
            user: {
              id: 70664,
              avatar: 'thumb_200-2-899-898_14b82f2d40b54bfbafc9db4499be3724.jpeg',
              name: '我有一个很长长长长长长长长长长长长长长的名字',
              username: 'rhainliu',
              state: 'active',
              blocked: false,
            },
            duration: null,
            badges: [],
          },
          invalidUsers: [],
        });
        api.get('/api/web/v1/projects/10712436/cc/users?ccType=MergeRequest&iid=1').reply(200, [
          { id: 202775, avatar: null, name: 'v_xinphou', username: 'v_xinphou', state: 'active' },
          { id: 265898, avatar: null, name: 'shayleehu', username: 'shayleehu', state: 'active' },
        ]);
        api.get('/api/web/v1/projects/10712436/reviews/1/tapds').reply(200, [
          {
            id: '6092',
            workspaceId: 10114641,
            sourceProjectId: 10712436,
            sourceId: 1,
            sourceType: 'mr',
            tapdId: '1010114641854938893',
            tapdType: 'story',
            name: 'Update 9813.md',
            status: 'planning',
            statusZh: '规划中',
          },
          {
            id: '6093',
            workspaceId: 20357985,
            sourceProjectId: 10712436,
            sourceId: 1,
            sourceType: 'mr',
            tapdId: '1020357985854929165',
            tapdType: 'story',
            name: 'ceshi  squash',
            status: 'planning',
            statusZh: '规划中',
          },
        ]);
      })
      .stdout()
      .command(['mr show', '1', '-R gongfeng/cli'])
      .it('cross project merge request exist', (ctx) => {
        expect(ctx.stdout).to.contain('更新文件 README.md');
        expect(ctx.stdout).to.contain('dev -> master');
        expect(ctx.stdout).to.contain('Author: rhainliu');
        expect(ctx.stdout).to.contain('Labels:  wewe, rrrr');
        expect(ctx.stdout).to.contain('Milestone: qeqwe');
        expect(ctx.stdout).to.contain('Review state: Approving');
        expect(ctx.stdout).to.contain(
          'Reviewers: v_ytingsu[V] [iMaster-Go] [iMaster-Java] [iRead-C++] [iRead-JS/TS] [iRead-OC](Approving)',
        );
        expect(ctx.stdout).to.contain('【Story】: Update 9813.md');
        expect(ctx.stdout).to.contain('Carbon Copy: v_xinphou,shayleehu');
      });
  });
});
