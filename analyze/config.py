from pathlib import Path


# ============================================================
# Repository paths
# ============================================================

ANALYZE_DIR = Path(__file__).resolve().parent
REPO_ROOT = ANALYZE_DIR.parent
DATA_DIR = REPO_ROOT / "data"

OUTPUT_DIR = ANALYZE_DIR / "outputs"
TABLE_DIR = OUTPUT_DIR / "tables"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
TABLE_DIR.mkdir(parents=True, exist_ok=True)


# ============================================================
# Network configuration
# ============================================================

INPUT_H = 28
INPUT_W = 28
INPUT_C = 1

CONV1_KERNEL = 5
CONV1_CIN = 1
CONV1_COUT = 3

POOL_SIZE = 2

CONV2_KERNEL = 5
CONV2_CIN = 3
CONV2_COUT = 3

FC_IN = 48
FC_OUT = 10


# ============================================================
# RTL fixed-point widths
# ============================================================

INPUT_BITS = 8

WEIGHT_BITS = 8
BIAS_BITS = 8

CONV1_ACC_BITS = 20
CONV1_OUT_BITS = 12

CONV2_PARTIAL_ACC_BITS = 20
CONV2_ACC_BITS = 20
CONV2_INTERNAL_BITS = 14
CONV2_OUT_BITS = 12

POOL_OUT_BITS = 12

FC_BUFFER_BITS = 14
FC_ACC_BITS = 20
FC_OUT_BITS = 12


# ============================================================
# RTL bit slicing
# ============================================================

# conv1.v:
# assign conv_out = calc_out[19:8] + bias
CONV1_SLICE_MSB = 19
CONV1_SLICE_LSB = 8

# conv2_calc:
# conv_out_calc <= calc_out[19:6]
CONV2_CALC_SLICE_MSB = 19
CONV2_CALC_SLICE_LSB = 6

# conv2_layer:
# conv2_out = conv_out[13:1] + bias
CONV2_LAYER_SLICE_MSB = 13
CONV2_LAYER_SLICE_LSB = 1

# fc.v:
# data_out <= calc_out[18:7]
FC_SLICE_MSB = 18
FC_SLICE_LSB = 7


# ============================================================
# Default evaluation files
# ============================================================

DEFAULT_SINGLE_IMAGE = DATA_DIR / "2_0.txt"
DEFAULT_DATASET = DATA_DIR / "input_1000.txt"