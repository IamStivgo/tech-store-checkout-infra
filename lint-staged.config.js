export default {
  '*.tf': ['terraform fmt', () => 'tflint --recursive'],
};
