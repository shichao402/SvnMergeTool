import color from '../src/color';
import { expect } from 'fancy-test';

describe('gong feng colors', () => {
  it('gray color', () => {
    expect(color.gray('hello')).to.include('hello');
  });

  it('brand color', () => {
    expect(color.brand('hello')).to.include('hello');
  });

  it('info color', () => {
    expect(color.info('hello')).to.include('hello');
  });

  it('warn color', () => {
    expect(color.warn('hello')).to.include('hello');
  });

  it('success color', () => {
    expect(color.success('hello')).to.include('hello');
  });

  it('error color', () => {
    expect(color.error('hello')).to.include('hello');
  });
});
