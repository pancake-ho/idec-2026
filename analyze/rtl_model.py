from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

from config import (
    INPUT_H,
    INPUT_W,
    CONV1_KERNEL,
    CONV1_ACC_BITS,
    CONV1_OUT_BITS,
    CONV1_SLICE_MSB,
    CONV1_SLICE_LSB,
    CONV2_KERNEL,
    CONV2_PARTIAL_ACC_BITS,
    CONV2_ACC_BITS,
    CONV2_INTERNAL_BITS,
    CONV2_OUT_BITS,
    CONV2_CALC_SLICE_MSB,
    CONV2_CALC_SLICE_LSB,
    CONV2_LAYER_SLICE_MSB,
    CONV2_LAYER_SLICE_LSB,
    FC_IN,
    FC_ACC_BITS,
    FC_OUT_BITS,
    FC_SLICE_MSB,
    FC_SLICE_LSB,
)

from fixed_point import (
    wrap_signed,
    part_select_signed,
)

from io_utils import RTLParameters


@dataclass
class RTLTrace:
    """
    Intermediate values for debugging and bit-width analysis.

    *_math:
        mathematical result before RTL register/wire truncation

    *_20:
        result after 20-bit RTL wrap

    Outputs such as conv1_out / conv2_out / logits:
        signed interpretation of the actual RTL bit pattern
    """

    input_image: np.ndarray

    conv1_acc_math: np.ndarray
    conv1_acc20: np.ndarray
    conv1_out: np.ndarray

    pool1: np.ndarray

    conv2_partial_math: np.ndarray
    conv2_partial20: np.ndarray
    conv2_full_math: np.ndarray
    conv2_acc20: np.ndarray
    conv2_internal14: np.ndarray
    conv2_out: np.ndarray

    pool2: np.ndarray

    fc_input: np.ndarray

    fc_acc_math: np.ndarray
    fc_acc20: np.ndarray
    logits: np.ndarray


class RTLReferenceCNN:
    """
    Functional fixed-point model of the provided RTL CNN.

    Important:
        This model reproduces the neural arithmetic/dataflow.

        It is NOT a cycle-accurate model of:
            valid
            buffers
            FSMs
            pipeline timing

        Those remain verified with Vivado RTL simulation.
    """

    def __init__(
        self,
        params: RTLParameters,
    ):
        self.p = params

    # ============================================================
    # Conv1
    # ============================================================

    def _conv1(
        self,
        image: np.ndarray,
    ):
        """
        RTL equivalent:

            8-bit unsigned pixel
                x
            signed 8-bit weight
                ->
            25-product accumulation
                ->
            signed 20-bit calc_out
                ->
            calc_out[19:8]
                ->
            + signed 8-bit bias
                ->
            12-bit output
        """

        image = np.asarray(
            image,
            dtype=np.int64,
        )

        if image.shape != (INPUT_H, INPUT_W):
            raise ValueError(
                f"Expected image shape {(INPUT_H, INPUT_W)}, "
                f"got {image.shape}"
            )

        if np.any(image < 0) or np.any(image > 255):
            raise ValueError(
                "Input image must contain unsigned 8-bit pixels."
            )

        # [24, 24, 5, 5]
        windows = sliding_window_view(
            image,
            (
                CONV1_KERNEL,
                CONV1_KERNEL,
            ),
        ).astype(np.int64)

        # weights:
        # [3, 5, 5]
        #
        # result:
        # [3, 24, 24]
        acc_math = np.einsum(
            "hwkl,okl->ohw",
            windows,
            self.p.conv1_w,
            dtype=np.int64,
            optimize=True,
        )

        # calc_out is declared signed [19:0]
        acc20 = wrap_signed(
            acc_math,
            CONV1_ACC_BITS,
        )

        # RTL:
        # calc_out[19:8]
        pre_bias = part_select_signed(
            acc20,
            source_bits=CONV1_ACC_BITS,
            msb=CONV1_SLICE_MSB,
            lsb=CONV1_SLICE_LSB,
        )

        out_math = (
            pre_bias
            + self.p.conv1_b[:, None, None]
        )

        # output port is 12 bits.
        # The next module interprets the same bit pattern as signed.
        out = wrap_signed(
            out_math,
            CONV1_OUT_BITS,
        )

        return (
            out,
            acc_math,
            acc20,
        )

    # ============================================================
    # MaxPool + ReLU
    # ============================================================

    @staticmethod
    def _maxpool_relu(
        x: np.ndarray,
    ) -> np.ndarray:
        """
        RTL maxpool_relu:

            2x2 maximum
                +
            ReLU:
                if max > 0:
                    max
                else:
                    0
        """

        x = np.asarray(
            x,
            dtype=np.int64,
        )

        if x.ndim != 3:
            raise ValueError(
                f"Expected [C,H,W], got {x.shape}"
            )

        channels, height, width = x.shape

        if height % 2 != 0 or width % 2 != 0:
            raise ValueError(
                f"Pooling input must have even H/W: {x.shape}"
            )

        # [C, H/2, 2, W/2, 2]
        patches = x.reshape(
            channels,
            height // 2,
            2,
            width // 2,
            2,
        )

        pooled = patches.max(
            axis=(2, 4)
        )

        # ReLU
        pooled = np.maximum(
            pooled,
            0,
        )

        return pooled.astype(np.int64)

    # ============================================================
    # Conv2
    # ============================================================

    def _conv2(
        self,
        x: np.ndarray,
    ):
        """
        RTL structure is important.

        For each output channel:

            input channel 0 -> 25 MAC -> signed 20-bit partial
            input channel 1 -> 25 MAC -> signed 20-bit partial
            input channel 2 -> 25 MAC -> signed 20-bit partial

                       three partial sums
                               |
                               v
                       signed 20-bit calc_out
                               |
                         calc_out[19:6]
                               |
                       signed 14-bit register
                               |
                          [13:1]
                               |
                             bias
                               |
                         12-bit output
        """

        x = np.asarray(
            x,
            dtype=np.int64,
        )

        if x.shape != (3, 12, 12):
            raise ValueError(
                f"Conv2 expected (3,12,12), got {x.shape}"
            )

        # [Cin, 8, 8, 5, 5]
        windows = sliding_window_view(
            x,
            (
                CONV2_KERNEL,
                CONV2_KERNEL,
            ),
            axis=(1, 2),
        ).astype(np.int64)

        # Weight:
        # [Cout, Cin, 5, 5]
        #
        # Produce each input-channel partial separately:
        #
        # [Cout, Cin, 8, 8]
        partial_math = np.einsum(
            "cxykl,ockl->ocxy",
            windows,
            self.p.conv2_w,
            dtype=np.int64,
            optimize=True,
        )

        # Each calc_out_1/2/3 is independently
        # declared signed [19:0].
        partial20 = wrap_signed(
            partial_math,
            CONV2_PARTIAL_ACC_BITS,
        )

        # This is useful for analysis only.
        # It is the mathematically full 75-MAC dot product.
        full_math = partial_math.sum(
            axis=1,
            dtype=np.int64,
        )

        # RTL calc_out is the sum of the three
        # already-width-limited partial wires.
        acc_from_partial = partial20.sum(
            axis=1,
            dtype=np.int64,
        )

        acc20 = wrap_signed(
            acc_from_partial,
            CONV2_ACC_BITS,
        )

        # RTL:
        # conv_out_calc <= calc_out[19:6]
        internal14 = part_select_signed(
            acc20,
            source_bits=CONV2_ACC_BITS,
            msb=CONV2_CALC_SLICE_MSB,
            lsb=CONV2_CALC_SLICE_LSB,
        )

        internal14 = wrap_signed(
            internal14,
            CONV2_INTERNAL_BITS,
        )

        # RTL layer:
        # conv2_out = conv_out[13:1] + exp_bias
        pre_bias = part_select_signed(
            internal14,
            source_bits=CONV2_INTERNAL_BITS,
            msb=CONV2_LAYER_SLICE_MSB,
            lsb=CONV2_LAYER_SLICE_LSB,
        )

        out_math = (
            pre_bias
            + self.p.conv2_b[:, None, None]
        )

        out = wrap_signed(
            out_math,
            CONV2_OUT_BITS,
        )

        return (
            out,
            partial_math,
            partial20,
            full_math,
            acc20,
            internal14,
        )

    # ============================================================
    # Fully Connected
    # ============================================================

    def _fully_connected(
        self,
        pool2: np.ndarray,
    ):
        """
        fc.v receives 3 values per valid pulse and stores:

            channel 0 -> buffer[0:15]
            channel 1 -> buffer[16:31]
            channel 2 -> buffer[32:47]

        Therefore flatten order is channel-major.
        """

        pool2 = np.asarray(
            pool2,
            dtype=np.int64,
        )

        if pool2.shape != (3, 4, 4):
            raise ValueError(
                f"FC expected Pool2 shape (3,4,4), "
                f"got {pool2.shape}"
            )

        # C-order:
        #
        # channel 0: 16 features
        # channel 1: 16 features
        # channel 2: 16 features
        fc_input = pool2.reshape(-1)

        if fc_input.size != FC_IN:
            raise AssertionError(
                f"FC input size={fc_input.size}"
            )

        # RTL:
        #
        # weight[out_idx*48 + i] * buffer[i]
        #
        # [10,48] @ [48]
        acc_math = (
            np.einsum(
                "oi,i->o",
                self.p.fc_w,
                fc_input,
                dtype=np.int64,
                optimize=True,
            )
            + self.p.fc_b
        )

        acc20 = wrap_signed(
            acc_math,
            FC_ACC_BITS,
        )

        # RTL:
        # data_out <= calc_out[18:7]
        logits = part_select_signed(
            acc20,
            source_bits=FC_ACC_BITS,
            msb=FC_SLICE_MSB,
            lsb=FC_SLICE_LSB,
        )

        logits = wrap_signed(
            logits,
            FC_OUT_BITS,
        )

        return (
            fc_input,
            acc_math,
            acc20,
            logits,
        )

    # ============================================================
    # Full network
    # ============================================================

    def forward(
        self,
        image: np.ndarray,
        return_trace: bool = False,
    ):

        # Conv1
        (
            conv1_out,
            conv1_acc_math,
            conv1_acc20,
        ) = self._conv1(image)

        # Pool1 + ReLU
        pool1 = self._maxpool_relu(
            conv1_out
        )

        # Conv2
        (
            conv2_out,
            conv2_partial_math,
            conv2_partial20,
            conv2_full_math,
            conv2_acc20,
            conv2_internal14,
        ) = self._conv2(pool1)

        # Pool2 + ReLU
        pool2 = self._maxpool_relu(
            conv2_out
        )

        # FC
        (
            fc_input,
            fc_acc_math,
            fc_acc20,
            logits,
        ) = self._fully_connected(pool2)

        # np.argmax returns the first maximum.
        #
        # This matches the current comparator behavior using:
        #     if(data_in > max_value)
        #
        # rather than >=.
        pred = int(
            np.argmax(logits)
        )

        if not return_trace:    
            return pred

        trace = RTLTrace(
            input_image=np.asarray(
                image,
                dtype=np.int64,
            ),

            conv1_acc_math=conv1_acc_math,
            conv1_acc20=conv1_acc20,
            conv1_out=conv1_out,

            pool1=pool1,

            conv2_partial_math=conv2_partial_math,
            conv2_partial20=conv2_partial20,
            conv2_full_math=conv2_full_math,
            conv2_acc20=conv2_acc20,
            conv2_internal14=conv2_internal14,
            conv2_out=conv2_out,

            pool2=pool2,

            fc_input=fc_input,

            fc_acc_math=fc_acc_math,
            fc_acc20=fc_acc20,
            logits=logits,
        )

        return pred, trace