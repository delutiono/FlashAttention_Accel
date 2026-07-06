import unittest

import low_precision_eval as lp


def make_outlier_tensor(rows=16, cols=64):
    tensor = []
    for r in range(rows):
        row = []
        for c in range(cols):
            base = ((r * 7 + c * 3) % 17 - 8) / 64.0
            if r >= rows // 2:
                base *= 12.0
            row.append(base)
        tensor.append(row)
    return tensor


class LowPrecisionEvalTest(unittest.TestCase):
    def test_block_quantization_improves_outlier_reconstruction(self):
        q = make_outlier_tensor()
        k = make_outlier_tensor()
        v = make_outlier_tensor()

        report = lp.evaluate_tensors(q, k, v, block_rows=8, use_hadamard=True)

        self.assertLess(report["block_int8"]["input_mae"], report["per_tensor_int8"]["input_mae"])
        self.assertLess(report["block_int8"]["bytes_total"], report["baseline_q8_8"]["bytes_total"])
        self.assertIn("output_mae", report["block_int8"])
        self.assertIn("block_int8_hadamard", report)
        self.assertGreater(report["block_int8"]["bandwidth_reduction"], 1.8)


if __name__ == "__main__":
    unittest.main()
