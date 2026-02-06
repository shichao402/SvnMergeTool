import { authToken } from '../src';
import netrc from 'netrc-parser';
import * as sinon from 'sinon';

describe('pre auth test', () => {
  it('get auth token success', async () => {
    const mock = sinon.mock(netrc);
    await authToken();
    mock.expects('load').once();
  });
});
