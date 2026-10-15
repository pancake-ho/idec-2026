"""The DASH adaptation contract; legacy MNIST shifts are not copied blindly."""
SOURCE_COMMIT = '0d345f1bb658d5772868c7ef939ac592b7a2bb19'
CLASSES = ('excellent', 'great', 'good', 'poor')
SHAPES = {'q1_sp': (2, 1, 5, 5), 'q2_sp': (3, 2, 5, 5),
          'q1_td': (2, 1, 49), 'q2_td': (3, 2, 49), 'qfc': (4, 48),
          'b1': (2,), 'b2': (3,), 'bfc': (4,)}
MODES = {
    'int8': dict(weight_bits=(8, 8, 8), activation_bits=(8, 8), prune=(0, 0, 0),
                 conv_coding='exact', fc_coding='exact'),
    'v25h': dict(weight_bits=(5, 6, 6), activation_bits=(8, 8), prune=(16, 8, 8),
                  conv_coding='pot1', fc_coding='sp2'),
}
# G coefficient widths inherited from the V25 transformed-domain layout.
LANE_BW8 = tuple(12 if i in {5,6,9,10} else
                 11 if i in {1,2,4,7,8,11,13,14,20,23,33,34} else
                 10 if i in {0,3,12,15,17,19,21,22,24,26,29,30,32,35,37,38,44} else
                 9 if i in {16,18,25,27,28,31,36,39,41,43,45,47} else 8
                 for i in range(49))
