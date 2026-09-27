// SPA routing without CloudFront custom error responses, which would also turn API errors
// into index.html: every path without a file extension is served by the SPA.
function handler(event) {
  var request = event.request;
  if (request.uri.indexOf('.') === -1) {
    request.uri = '/index.html';
  }
  return request;
}
