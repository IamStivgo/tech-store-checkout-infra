// Initial code of the api function. Terraform only uses it to create the function; the api
// repository deploys the real bundle, which must export `handler` from lambda.js as well.
exports.handler = async () => ({
  statusCode: 503,
  headers: {
    'content-type': 'application/problem+json',
    'cache-control': 'no-store',
  },
  body: JSON.stringify({
    type: 'about:blank',
    title: 'Service Unavailable',
    status: 503,
    detail: 'The API has not been deployed yet.',
  }),
});
