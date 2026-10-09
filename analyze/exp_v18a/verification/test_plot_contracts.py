"""Guard plot scope and exact-SQNR handling with explicitly synthetic fixtures."""
import csv
import tempfile
import unittest
from pathlib import Path
import numpy as np
from exp_v18a.plots.data import PlotData
from exp_v18a.plots.sensitivity import single_factor_curves
from exp_v18a.plots.style import plt


class PlotContracts(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data=PlotData(Path(self.temp.name))
        self.base=dict(candidate='baseline',kind='baseline',rounding='floor',w1='8',w2='8',wfc='8',
                       a_pool1='11',a_pool2='11',calibration_candidate_correct='57',calibration_images='60',
                       calibration_logit_sqnr_db='',calibration_logit_exact='1',proxy_bitproduct_reduction_pct='0')
        self.rows=[self.base]
        for bits,correct,sqnr in [(7,58,30),(6,56,20),(5,55,10)]:
            self.rows.append(dict(self.base,candidate=f'W{bits}_8_8_even',kind='weight_single',
                                  rounding='even',w1=str(bits),calibration_candidate_correct=str(correct),
                                  calibration_logit_sqnr_db=str(sqnr),calibration_logit_exact='0'))
        # A joint-layer point must NEVER become the Conv1-only W5 point.
        self.rows.append(dict(self.base,candidate='W5_5_5_even',kind='weight_grid',rounding='even',
                              w1='5',w2='5',wfc='5',calibration_candidate_correct='1',
                              calibration_logit_sqnr_db='1',calibration_logit_exact='0'))
        with (self.data.out/'sensitivity.csv').open('w',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=list(self.base))
            writer.writeheader()
            writer.writerows(self.rows)
        self.fig=single_factor_curves(self.data,True)[0][1]
        self.addCleanup(plt.close,self.fig)

    def test_calibration_denominator_is_unique_count(self):
        values=self.fig.axes[0].lines[0].get_ydata()
        np.testing.assert_allclose(values,[95,100*58/60,100*56/60,100*55/60])

    def test_joint_candidate_not_used_as_single_factor(self):
        self.assertAlmostEqual(self.fig.axes[0].lines[0].get_ydata()[-1],100*55/60)

    def test_exact_sqnr_not_replaced_with_zero(self):
        values=self.fig.axes[1].lines[0].get_ydata()
        self.assertTrue(np.isnan(values[0]))
        np.testing.assert_array_equal(values[1:],[30,20,10])

    def test_no_shared_reduction_remains_zero(self):
        np.testing.assert_array_equal(self.fig.axes[2].lines[0].get_ydata(),[0,0,0,0])

    def test_duplicate_representatives_fail(self):
        with (self.data.out/'selected_image_decisions.csv').open('w',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['image_index'])
            writer.writeheader()
            writer.writerows([{'image_index':0},{'image_index':0}])
        with self.assertRaisesRegex(ValueError,'unique representatives'):
            self.data.unique_decisions()


if __name__=='__main__':
    unittest.main()
