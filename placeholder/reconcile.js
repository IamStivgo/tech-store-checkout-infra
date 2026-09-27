// Initial code of the reconcile function. Terraform only uses it to create the function; the
// api repository deploys the real bundle, which must export `handler` from reconcile.js as well.
exports.handler = async () => ({ expired: 0, synced: 0, failed: 0 });
