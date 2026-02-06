import { normalizeProjectPath } from '../src';
import { expect } from 'fancy-test';

describe('gong feng test', () => {
  it('normalize project path', () => {
    expect(normalizeProjectPath('')).to.equal('');
    expect(normalizeProjectPath('/a')).to.equal('%2Fa');
    expect(normalizeProjectPath('a/b')).to.equal('a%2Fb');
    expect(normalizeProjectPath('a/b/c')).to.equal('a%2Fb%2Fc');
    expect(normalizeProjectPath('a/b/c/')).to.equal('a%2Fb%2Fc%2F');
  });
});
