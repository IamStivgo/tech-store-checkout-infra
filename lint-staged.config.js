export default {
  '*.{tf,tftest.hcl}': ['terraform fmt', () => 'tflint --recursive'],
};
