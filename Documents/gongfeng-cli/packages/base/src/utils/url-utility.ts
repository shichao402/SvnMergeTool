// Returns a decoded url parameter value
// - Treats '+' as '%20'
function decodeUrlParameter(val: string) {
  return decodeURIComponent(val.replace(/\+/g, '%20'));
}

/**
 * Merges a URL to a set of params replacing value for
 * those already present.
 *
 * Also removes `null` param values from the resulting URL.
 *
 * @param {Object} params - url keys and value to merge
 * @param {String} url
 */
export function mergeUrlParams(params: Record<string, any>, url: string) {
  const re = /^([^?#]*)(\?[^#]*)?(.*)/;
  const merged: Record<string, string> = {};
  const [, fullpath, query, fragment] = url.match(re) || [];

  if (query) {
    query
      .substr(1)
      .split('&')
      .forEach((part) => {
        if (part.length) {
          const kv = part.split('=');
          merged[decodeUrlParameter(kv[0])] = decodeUrlParameter(kv.slice(1).join('='));
        }
      });
  }

  Object.assign(merged, params);

  const newQuery = Object.keys(merged)
    .filter((key) => merged[key] !== null)
    .map((key) => `${encodeURIComponent(key)}=${encodeURIComponent(merged[key])}`)
    .join('&');

  if (newQuery) {
    return `${fullpath}?${newQuery}${fragment}`;
  }
  return `${fullpath}${fragment}`;
}

export function getUrlWithAdTag(url: string) {
  return mergeUrlParams({ ADTAG: 'gf-cli' }, url);
}
