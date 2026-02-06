import { expect, test } from '@oclif/test';
import { shell } from '@tencent/gongfeng-cli-base';
import * as util from '../src/util';
import * as sinon from 'sinon';
import * as base from '@tencent/gongfeng-cli-base';
import { fixRelativePath } from '../src/util';

describe('util test', () => {
  test.it('test fix relative path', () => {
    const path = '/user/test';
    const a = fixRelativePath(path, '--- /user/test/a.txt');
    expect(a).to.be.equal('--- a.txt');
    const b = fixRelativePath(path, '+++ /user/test/b.txt');
    expect(b).to.be.equal('+++ b.txt');
    const c = fixRelativePath(path, '--- \\user\\test\\e\\a.txt');
    expect(c).to.be.equal('--- e/a.txt');
    const d = fixRelativePath(path, '+++ https://git.woa.com/e/a.txt');
    expect(d).to.be.equal('+++ https://git.woa.com/e/a.txt');
  });

  test.it('get st files', async () => {
    const diffs = ['A  +    /user/test/a.txt', '?       /user/test/b/b.txt'];
    const files = util.getFilesFromDiffSt(diffs);
    const expectedFiles = ['/user/test/a.txt', '/user/test/b/b.txt'];
    expect(files).to.deep.equal(expectedFiles);
  });
  test.it('test get st data', () => {
    const path = '/user/test';
    const lines = [
      'A  +    /user/test/a.txt',
      '?       /user/test/b/b.txt',
      'D       /user/test/a/c/d/u.txt',
      'A  +    /user/test/a/c/k/j.txt',
    ];
    const files = util.getFilesFromDiffSt(lines);
    const [diffLines, currFiles] = util.filterStData(path, lines, files, ['a.txt', 'b'], ['c']);
    expect(diffLines).to.deep.equal(['A  +    a.txt', '?       b/b.txt']);
    expect(currFiles).to.deep.equal(['a.txt', 'b/b.txt']);

    const [diffLines2, currFiles2] = util.filterStData(path, lines, files, [], ['b']);
    expect(diffLines2).to.deep.equal(['A  +    a.txt', 'D       a/c/d/u.txt', 'A  +    a/c/k/j.txt']);
    expect(currFiles2).to.deep.equal(['a.txt', 'a/c/d/u.txt', 'a/c/k/j.txt']);
  });
  test.it('filter files without filter', () => {
    const path = '/user/test';
    const diffFiles = [
      '/user/test/a.txt',
      '/user/test/b/b.txt',
      '/user/test/a/c/d/u.txt',
      '/user/test/e/c.txt',
      '/user/test/e/f/g/c.txt',
    ];
    const files = util.filterFiles(path, diffFiles);
    expect(files).to.deep.equal(diffFiles);
  });

  test.it('filter files with filter', () => {
    const path = '/user/test';
    const diffFiles = [
      '/user/test/a.txt',
      '/user/test/b/b.txt',
      '/user/test/a/c/d/u.txt',
      '/user/test/e/c.txt',
      '/user/test/e/f/g/c.txt',
    ];
    const fFiles = ['a.txt', 'a', 'b'];
    const files = util.filterFiles(path, diffFiles, fFiles);
    expect(files).to.deep.equal(['/user/test/a.txt', '/user/test/b/b.txt', '/user/test/a/c/d/u.txt']);
  });

  test.it('skip files without skips', () => {
    const path = '/user/test';
    const diffFiles = [
      '/user/test/a.txt',
      '/user/test/b/b.txt',
      '/user/test/a/c/d/u.txt',
      '/user/test/e/c.txt',
      '/user/test/e/f/g/c.txt',
    ];
    const files = util.filterSkipFiles(path, diffFiles);
    expect(files).to.deep.equal(diffFiles);
  });

  test.it('skip files with skips', () => {
    const path = '/user/test';
    const diffFiles = [
      '/user/test/a.txt',
      '/user/test/b/b.txt',
      '/user/test/a/c/d/u.txt',
      '/user/test/e/c.txt',
      '/user/test/e/f/g/c.txt',
    ];
    const skips = ['a.txt', 'b'];
    const files = util.filterSkipFiles(path, diffFiles, skips);
    expect(files).to.deep.equal(['/user/test/a/c/d/u.txt', '/user/test/e/c.txt', '/user/test/e/f/g/c.txt']);
  });

  test.it('filter modify windows data', () => {
    const path = 'D:/svntt/trunk';
    const diffLines = [
      'Index: D:/svntt/trunk/fddf.txt',
      '===================================================================',
      '--- D:/svntt/trunk/fddf.txt\t(revision 41)',
      '+++ D:/svntt/trunk/fddf.txt\t(working copy)',
      '@@ -1,2 +1,3 @@',
      ' dfgadfgfdgga',
      '-document.querySelectorAll("a[is-tapdlink=true]").forEach(item => item.drawNormalLink())',
      '\\ No newline at end of file',
      '+document.querySelectorAll("a[is-tapdlink=true]").forEach(item => item.drawNormalLink())',
      '+1',
      '\\ No newline at end of file',
    ];
    const diffFiles = shell.getFilenamesFromDiff(diffLines);
    const [lines, files] = util.filterData(path, diffLines, diffFiles, [], []);
    const expectedLines = [
      'Index: fddf.txt',
      '===================================================================',
      '--- fddf.txt\t(revision 41)',
      '+++ fddf.txt\t(working copy)',
      '@@ -1,2 +1,3 @@',
      ' dfgadfgfdgga',
      '-document.querySelectorAll("a[is-tapdlink=true]").forEach(item => item.drawNormalLink())',
      '\\ No newline at end of file',
      '+document.querySelectorAll("a[is-tapdlink=true]").forEach(item => item.drawNormalLink())',
      '+1',
      '\\ No newline at end of file',
    ];
    for (let i = 0; i < lines.length; i++) {
      expect(lines[i]).to.equal(expectedLines[i]);
    }
    expect(files).to.deep.equal(['fddf.txt']);
  });

  test.it('filter modify windows data', () => {
    const path = 'D:/svnprojects';
    const diffLines = [
      'Index: D:/svnprojects/trunk/test.txt',
      '===================================================================',
      '--- D:/svnprojects/trunk/test.txt\t(nonexistent)',
      '+++ D:/svnprojects/trunk/test.txt\t(working copy)',
      '@@ -0,0 +1,11 @@',
      '+fdasfda',
      '+',
      '+fasdfas',
      '+fda',
      '+f',
      '+safd',
      '+sa',
      '+fdsa',
      '+f',
      '+saf',
      '+sa',
      'Index: D:/svnprojects/trunk/test2.txt',
      '===================================================================',
      '--- D:/svnprojects/trunk/test2.txt\t(nonexistent)',
      '+++ D:/svnprojects/trunk/test2.txt\t(working copy)',
      '@@ -0,0 +1,15 @@',
      '+fasfa',
      '+',
      '+fadfadfsafsafdsafaf',
      '+',
      '+',
      '+fadsfasd',
      '+f',
      '+fa',
      '+sf',
      '+das',
      '+fas',
      '+f',
      '+sa',
      '+fda',
      '+f',
      '\\ No newline at end of file',
    ];
    const diffFiles = shell.getFilenamesFromDiff(diffLines);
    const [lines, files] = util.filterData(path, diffLines, diffFiles, [], []);
    const expectedLines = [
      'Index: trunk/test.txt',
      '===================================================================',
      '--- trunk/test.txt\t(nonexistent)',
      '+++ trunk/test.txt\t(working copy)',
      '@@ -0,0 +1,11 @@',
      '+fdasfda',
      '+',
      '+fasdfas',
      '+fda',
      '+f',
      '+safd',
      '+sa',
      '+fdsa',
      '+f',
      '+saf',
      '+sa',
      'Index: trunk/test2.txt',
      '===================================================================',
      '--- trunk/test2.txt\t(nonexistent)',
      '+++ trunk/test2.txt\t(working copy)',
      '@@ -0,0 +1,15 @@',
      '+fasfa',
      '+',
      '+fadfadfsafsafdsafaf',
      '+',
      '+',
      '+fadsfasd',
      '+f',
      '+fa',
      '+sf',
      '+das',
      '+fas',
      '+f',
      '+sa',
      '+fda',
      '+f',
      '\\ No newline at end of file',
    ];
    for (let i = 0; i < lines.length; i++) {
      expect(lines[i]).to.equal(expectedLines[i]);
    }
    expect(files).to.deep.equal(['trunk/test.txt', 'trunk/test2.txt']);
  });

  test.it('filter modify data', () => {
    const path = '/user/test';
    const diffLines = [
      'Index: /user/test/测试.txt',
      '===================================================================',
      '--- /user/test/测试.txt\t(revision 37)',
      '+++ /user/test/测试.txt\t(working copy)',
      '@@ -1 +1,8 @@',
      'test',
      '+ljlkj',
      '+fda',
      '+fd',
      '+as',
      '+fdas',
      '+f',
      '+asfd',
      'Index: /user/test/测试1.txt',
      '===================================================================',
      '--- /user/test/测试1.txt\t(revision 37)',
      '+++ /user/test/测试1.txt\t(working copy)',
      '@@ -1 +1,11 @@',
      '-test',
      '+dfadf',
      '+fdafa',
      '+ads',
      '+fasf',
      '+asf',
      '+asf',
      '+f',
      '+as',
      '+dfa',
      '+sf',
      '+testd',
    ];
    const diffFiles = shell.getFilenamesFromDiff(diffLines);
    const [lines, files] = util.filterData(path, diffLines, diffFiles, ['测试1.txt'], ['测试.txt']);
    const expectedLines = [
      'Index: 测试1.txt',
      '===================================================================',
      '--- 测试1.txt\t(revision 37)',
      '+++ 测试1.txt\t(working copy)',
      '@@ -1 +1,11 @@',
      '-test',
      '+dfadf',
      '+fdafa',
      '+ads',
      '+fasf',
      '+asf',
      '+asf',
      '+f',
      '+as',
      '+dfa',
      '+sf',
      '+testd',
    ];
    for (let i = 0; i < lines.length; i++) {
      expect(lines[i]).to.equal(expectedLines[i]);
    }
    expect(files).to.deep.equal(['测试1.txt']);
  });

  test
    .do(() => {
      sinon.stub(base, 'shell').value({
        ...shell,
        getFileSvnStatus: () => {
          return ['A       /Users/rhainliu/test/svn/trunk/jimcjzheng/antlr-2.7.7.jar'];
        },
        getSvnInfo: () => {
          return [
            'Path: /Users/rhainliu/test/svn/trunk/jimcjzheng/antlr-2.7.7.jar',
            'Name: antlr-2.7.7.jar',
            'Working Copy Root Path: /Users/rhainliu/test/svn/trunk',
            'URL: https://svn.woa.com/potTestGroupSz1/test_proj/trunk/jimcjzheng/antlr-2.7.7.jar',
            'Relative URL: ^/trunk/jimcjzheng/antlr-2.7.7.jar',
            'Repository Root: https://svn.woa.com/potTestGroupSz1/test_proj',
            'Repository UUID: 4560d9ea-116d-11ed-bfd8-958663996959',
            'Revision: 37',
            'Node Kind: file',
            'Schedule: delete',
            'Last Changed Author: rhainliu',
            'Last Changed Rev: 38',
            'Last Changed Date: 2023-10-19 09:52:37 +0800 (Thu, 19 Oct 2023)',
            'Checksum: 83cd2cd674a217ade95a4bb83a8a14f351f48bd0',
            '',
          ];
        },
      });
    })
    .it('add binary file test', () => {
      const path = '/Users/rhainliu/test/svn/trunk/jimcjzheng';
      const diffLines = [
        'Index: /Users/rhainliu/test/svn/trunk/jimcjzheng/antlr-2.7.7.jar',
        '===================================================================',
        '无法显示: 文件标记为二进制类型。',
        'svn:mime-type = application/octet-stream',
        '',
        'Property changes on: /Users/rhainliu/test/svn/trunk/jimcjzheng/antlr-2.7.7.jar',
        '___________________________________________________________________',
        'Added: svn:mime-type',
        '## -0,0 +1 ##',
        '+application/octet-stream',
        '\\ No newline at end of property',
        'Index: /Users/rhainliu/test/svn/trunk/jimcjzheng/测试.txt',
        '===================================================================',
        '--- /Users/rhainliu/test/svn/trunk/jimcjzheng/测试.txt\t(revision 37)',
        '+++ /Users/rhainliu/test/svn/trunk/jimcjzheng/测试.txt\t(working copy)',
        '@@ -1 +1,3 @@',
        'test',
        '+ljlkj',
        '+fda',
        'Index: /Users/rhainliu/test/svn/trunk/jimcjzheng/测试1.txt',
        '===================================================================',
        '--- /Users/rhainliu/test/svn/trunk/jimcjzheng/测试1.txt\t(revision 37)',
        '+++ /Users/rhainliu/test/svn/trunk/jimcjzheng/测试1.txt\t(working copy)',
        '@@ -1 +1 @@',
        '-test',
        '+dfa',
        '\\ No newline at end of file',
      ];
      const diffFiles = shell.getFilenamesFromDiff(diffLines);
      const [lines, files] = util.filterData(path, diffLines, diffFiles, [], ['测试.txt']);
      expect(files).to.deep.equal(['antlr-2.7.7.jar', '测试1.txt']);
      const expectLines = [
        'Index: antlr-2.7.7.jar',
        '===================================================================',
        '--- antlr-2.7.7.jar\t(revision none)',
        '+++ antlr-2.7.7.jar\t(working copy)',
        '@@ -0,0 +1,0 @@',
        '+',
        'Index: 测试1.txt',
        '===================================================================',
        '--- 测试1.txt\t(revision 37)',
        '+++ 测试1.txt\t(working copy)',
        '@@ -1 +1 @@',
        '-test',
        '+dfa',
        '\\ No newline at end of file',
      ];
      for (let i = 0; i < lines.length; i++) {
        expect(lines[i]).to.equal(expectLines[i]);
      }
    });

  test
    .do(() => {
      sinon.stub(base, 'shell').value({
        ...shell,
        getFileSvnStatus: () => {
          return ['D       /Users/rhainliu/test/svn/trunk/jimcjzheng/antlr-2.7.7.jar'];
        },
        getSvnInfo: () => {
          return [
            'Path: /Users/rhainliu/test/svn/trunk/jimcjzheng/antlr-2.7.7.jar',
            'Name: antlr-2.7.7.jar',
            'Working Copy Root Path: /Users/rhainliu/test/svn/trunk',
            'URL: https://svn.woa.com/potTestGroupSz1/test_proj/trunk/jimcjzheng/antlr-2.7.7.jar',
            'Relative URL: ^/trunk/jimcjzheng/antlr-2.7.7.jar',
            'Repository Root: https://svn.woa.com/potTestGroupSz1/test_proj',
            'Repository UUID: 4560d9ea-116d-11ed-bfd8-958663996959',
            'Revision: 38',
            'Node Kind: file',
            'Schedule: delete',
            'Last Changed Author: rhainliu',
            'Last Changed Rev: 38',
            'Last Changed Date: 2023-10-19 09:52:37 +0800 (Thu, 19 Oct 2023)',
            'Checksum: 83cd2cd674a217ade95a4bb83a8a14f351f48bd0',
            '',
          ];
        },
      });
    })
    .it('delete binary file', () => {
      const path = '/Users/rhainliu/test/svn/trunk/jimcjzheng';
      const diffLines = [
        'Index: /Users/rhainliu/test/svn/trunk/jimcjzheng/antlr-2.7.7.jar',
        '===================================================================',
        'Cannot display: file marked as a binary type.',
        'svn:mime-type = application/octet-stream',
        '',
        'Property changes on: /Users/rhainliu/test/svn/trunk/jimcjzheng/antlr-2.7.7.jar',
        '___________________________________________________________________',
        'Deleted: svn:mime-type',
        '## -1 +0,0 ##',
        '-application/octet-stream',
        ' No newline at end of property',
        'Index: /Users/rhainliu/test/svn/trunk/jimcjzheng/测试1.txt',
        '===================================================================',
        '--- /Users/rhainliu/test/svn/trunk/jimcjzheng/测试1.txt\t(revision 38)',
        '+++ /Users/rhainliu/test/svn/trunk/jimcjzheng/测试1.txt\t(working copy)',
        '@@ -1 +1,3 @@',
        '-dfa',
        ' No newline at end of file',
        '+dfa',
        '+2',
        '+2',
        ' No newline at end of file',
      ];
      const diffFiles = shell.getFilenamesFromDiff(diffLines);
      const [lines, files] = util.filterData(path, diffLines, diffFiles, [], []);
      expect(files).to.deep.equal(['antlr-2.7.7.jar', '测试1.txt']);
      const expectedLines = [
        'Index: antlr-2.7.7.jar',
        '===================================================================',
        '--- antlr-2.7.7.jar\t(revision 38)',
        '+++ antlr-2.7.7.jar\t(working copy)',
        '@@ -1,1 +0,0 @@',
        '-',
        'Index: 测试1.txt',
        '===================================================================',
        '--- 测试1.txt\t(revision 38)',
        '+++ 测试1.txt\t(working copy)',
        '@@ -1 +1,3 @@',
        '-dfa',
        ' No newline at end of file',
        '+dfa',
        '+2',
        '+2',
        ' No newline at end of file',
      ];
      for (let i = 0; i < lines.length; i++) {
        expect(lines[i]).to.equal(expectedLines[i]);
      }
    });

  test
    .do(() => {
      sinon.stub(base, 'shell').value({
        ...shell,
        getFileSvnStatus: () => {
          return ['A  +    /Users/rhainliu/test/svn/trunk/jimcjzheng/t1_1.txt'];
        },
        getSvnInfo: () => {
          return [
            'Path: /Users/rhainliu/test/svn/trunk/jimcjzheng/t1_1.txt',
            'Name: t1_1.txt',
            'Working Copy Root Path: /Users/rhainliu/test/svn/trunk',
            'URL: https://svn.woa.com/potTestGroupSz1/test_proj/trunk/jimcjzheng/t1_1.txt',
            'Relative URL: ^/trunk/jimcjzheng/t1_1.txt',
            'Repository Root: https://svn.woa.com/potTestGroupSz1/test_proj',
            'Repository UUID: 4560d9ea-116d-11ed-bfd8-958663996959',
            'Revision: 37',
            'Node Kind: file',
            'Schedule: add',
            'Copied From URL: https://svn.woa.com/potTestGroupSz1/test_proj/trunk/t1_1.txt',
            'Copied From Rev: 37',
            'Last Changed Author: jimcjzheng',
            'Last Changed Rev: 33',
            'Last Changed Date: 2022-11-30 15:38:55 +0800 (Wed, 30 Nov 2022)',
            'Text Last Updated: 2023-10-16 17:28:02 +0800 (Mon, 16 Oct 2023)',
            'Checksum: 1fd67bfede2084c6b53bd43b44413f6f843e7cce',
          ];
        },
      });
    })
    .it('test copy file', () => {
      const path = '/Users/rhainliu/test/svn/trunk/jimcjzheng';
      const diffLines = [
        'Index: /Users/rhainliu/test/svn/trunk/jimcjzheng/t1_1.txt',
        '===================================================================',
        '--- /Users/rhainliu/test/svn/trunk/jimcjzheng/t1_1.txt\t(revision 37)',
        '+++ /Users/rhainliu/test/svn/trunk/jimcjzheng/t1_1.txt\t(working copy)',
        '@@ -1,2 +1,4 @@',
        'update file after lock file',
        'test',
        '+',
        '+fas',
        ' No newline at end of file',
      ];
      const diffFiles = shell.getFilenamesFromDiff(diffLines);
      const [lines, files] = util.filterData(path, diffLines, diffFiles, [], []);
      expect(files).to.deep.equal(['t1_1.txt']);
      const expectedLines = [
        'Index: t1_1.txt',
        '===================================================================',
        '--- https://svn.woa.com/potTestGroupSz1/test_proj/trunk/t1_1.txt\t(revision 37)',
        '+++ t1_1.txt\t(working copy)',
        '@@ -1,2 +1,4 @@',
        'update file after lock file',
        'test',
        '+',
        '+fas',
        ' No newline at end of file',
      ];
      for (let i = 0; i < lines.length; i++) {
        expect(lines[i]).to.equal(expectedLines[i]);
      }
    });
});
