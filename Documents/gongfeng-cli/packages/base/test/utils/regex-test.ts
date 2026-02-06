import { getCaptures } from '../../src/utils/regex';
import { expect } from 'chai';

describe('getCaptures', () => {
  let bodyOfText: string;
  const regex = /(.+):matching:(.+)/gi;
  const subject = () => getCaptures(bodyOfText, regex);

  describe('with matches', () => {
    beforeEach(() => {
      bodyOfText = 'capture me!:matching:capture me too!\nalso capture me!:matching:also capture me too!\n';
    });
    it('returns all captures', () => {
      expect(subject()).to.deep.equal([
        ['capture me!', 'capture me too!'],
        ['also capture me!', 'also capture me too!'],
      ]);
    });
  });

  describe('with no matches', () => {
    beforeEach(() => {
      bodyOfText = ' ';
    });
    it('returns empty array', () => {
      expect(subject()).to.deep.equal([]);
    });
  });

  it('will error where a non-global regex is provide', () => {
    const regex = /(.+):matching:(.+)/;
    bodyOfText = 'capture me!:matching:capture me too!\nalso capture me!:matching:also capture me too!\n';
    expect(() => getCaptures(bodyOfText, regex)).to.throw();
  });
});
