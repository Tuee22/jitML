extern "C" __global__ void jitml_identity(const double* input, double* output) {
  output[0] = input[0];
}
