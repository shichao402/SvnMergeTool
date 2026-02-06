import { expect } from 'chai';
import { GitProgressParser, IGitProgress, IGitProgressInfo, parse } from '../../src/progress';

describe('GitProgressParser', () => {
  it('requires at least one steps', () => {
    expect(() => new GitProgressParser([])).to.throw();
  });

  it('parses progress with one step', () => {
    const parser = new GitProgressParser([{ title: 'remote: Compressing objects', weight: 1 }]);
    const result = parser.parse('remote: Compressing objects:  72% (16/22)');
    expect(result).to.have.property('percent', 16 / 22);
  });

  it('parses progress with several steps', () => {
    const parser = new GitProgressParser([
      { title: 'remote: Compressing objects', weight: 0.5 },
      { title: 'Receiving objects', weight: 0.5 },
    ]);
    let result = parser.parse('remote: Compressing objects:  72% (16/22)');
    expect(result.kind).to.equal('progress');
    expect((result as IGitProgress).percent).to.equal(16 / 22 / 2);

    result = parser.parse('Receiving objects:  99% (166741/167587), 267.24 MiB | 2.40 MiB/s');

    expect(result.kind).to.equal('progress');
    expect((result as IGitProgress).percent).to.equal(0.5 + 166741 / 167587 / 2);
  });

  it('enforces ordering of steps', () => {
    const parser = new GitProgressParser([
      { title: 'remote: Compressing objects', weight: 0.5 },
      { title: 'Receiving objects', weight: 0.5 },
    ]);

    let result = parser.parse('remote: Compressing objects:  72% (16/22)');
    expect(result.kind).to.equal('progress');
    expect((result as IGitProgress).percent).to.equal(16 / 22 / 2);

    result = parser.parse('Receiving objects:  99% (166741/167587), 267.24 MiB | 2.40 MiB/s');

    expect(result.kind).to.equal('progress');
    expect((result as IGitProgress).percent).to.equal(0.5 + 166741 / 167587 / 2);

    result = parser.parse('remote: Compressing objects:  72% (16/22)');

    expect(result.kind).to.equal('context');
  });

  it('parses progress with no total', () => {
    const result = parse('remote: Counting objects: 167587');

    const progress: IGitProgressInfo = {
      title: 'remote: Counting objects',
      text: 'remote: Counting objects: 167587',
      value: 167587,
      done: false,
      percent: undefined,
      total: undefined,
    };
    expect(result).to.deep.equal(progress);
  });

  it('parses final progress with no total', () => {
    const result = parse('remote: Counting objects: 167587, done.');

    const progress: IGitProgressInfo = {
      title: 'remote: Counting objects',
      text: 'remote: Counting objects: 167587, done.',
      value: 167587,
      done: true,
      percent: undefined,
      total: undefined,
    };
    expect(result).to.deep.equal(progress);
  });

  it('parses progress with total', () => {
    const result = parse('remote: Compressing objects:  72% (16/22)');

    const progress: IGitProgressInfo = {
      title: 'remote: Compressing objects',
      text: 'remote: Compressing objects:  72% (16/22)',
      value: 16,
      done: false,
      percent: 72,
      total: 22,
    };
    expect(result).to.deep.equal(progress);
  });

  it('parses final with total', () => {
    const result = parse('remote: Compressing objects: 100% (22/22), done.');

    const progress: IGitProgressInfo = {
      title: 'remote: Compressing objects',
      text: 'remote: Compressing objects: 100% (22/22), done.',
      value: 22,
      done: true,
      percent: 100,
      total: 22,
    };
    expect(result).to.deep.equal(progress);
  });

  it('parses with total and throughput', () => {
    const result = parse('Receiving objects:  99% (166741/167587), 267.24 MiB | 2.40 MiB/s');

    const progress: IGitProgressInfo = {
      title: 'Receiving objects',
      text: 'Receiving objects:  99% (166741/167587), 267.24 MiB | 2.40 MiB/s',
      value: 166741,
      done: false,
      percent: 99,
      total: 167587,
    };
    expect(result).to.deep.equal(progress);
  });

  it('parses final with total and throughput', () => {
    const result = parse('Receiving objects: 100% (167587/167587), 279.67 MiB | 2.43 MiB/s, done.');

    const progress: IGitProgressInfo = {
      title: 'Receiving objects',
      text: 'Receiving objects: 100% (167587/167587), 279.67 MiB | 2.43 MiB/s, done.',
      value: 167587,
      done: true,
      percent: 100,
      total: 167587,
    };
    expect(result).to.deep.equal(progress);
  });

  it('does not parse things that are not progress', () => {
    const result = parse('remote: Total 167587 (delta 19), reused 11 (delta 11), pack-reused 167554         ');
    expect(result).to.equal(null);
  });
});
