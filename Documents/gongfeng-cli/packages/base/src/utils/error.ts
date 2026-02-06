export function getTraceId(e: any) {
  if (!e.response) {
    return '';
  }
  if (!e.response.headers) {
    return '';
  }
  return e.response.headers['x-traceid'];
}

export function getErrorMessage(e: any) {
  if (!e.response) {
    return '';
  }
  const { data } = e.response;
  if (!data) {
    return '';
  }
  return data.message ?? '';
}
