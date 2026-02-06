import { expect } from 'fancy-test';
import { truncateHalfAngleString } from '../../src';

describe('truncateHalfAngleString', () => {
  it('long half angle string', () => {
    expect(truncateHalfAngleString('hello world', 5)).to.equal('hell…');
  });

  it('long full angle string', () => {
    expect(truncateHalfAngleString('你好，世界', 5)).to.equal('你好…');
  });

  it('long string that mix half angle and full angle char', () => {
    expect(truncateHalfAngleString('我是 abc', 7)).to.equal('我是 a…');
  });

  it('empty string', () => {
    expect(truncateHalfAngleString('', 5)).to.equal('');
  });

  it('short half angle string', () => {
    expect(truncateHalfAngleString('hello world', 100)).to.equal('hello world');
  });

  it('short full angle string', () => {
    expect(truncateHalfAngleString('你好，世界', 100)).to.equal('你好，世界');
  });

  it('short string that mix half angle and full angle char', () => {
    expect(truncateHalfAngleString('我是 abc', 100)).to.equal('我是 abc');
  });

  it('set ellipsis', () => {
    expect(truncateHalfAngleString('hello world', 5, '...')).to.equal('he...');
  });

  it('maxLength must be greater than ellipsis length', () => {
    // 如果被测的方法在某些条件下抛出错误，则需要用 () => { func() } 包裹，不能直接 expect(func()).to.throw()。参考：https://www.chaijs.com/api/bdd/#method_throw
    expect(() => truncateHalfAngleString('hello world', 0, '...')).to.throw('maxLength must be greater than 3');
  });
});
