"""Meaningful numerical-contract checks, including independent dense-vs-transform arithmetic."""
import copy
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
import numpy as np
import torch
from v25.model import V25DASH
from v25.coding import quantize,single_terms,shift_products
from v25.transforms import BM,GM,inverse
from v25.integer import rne,infer,infer_spatial,export,load,validate,range_report
from v25.hardware import generate_engine
from v25.train import crosscheck
from v25.spec import LANE_BW8

class IntegerContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2);torch.manual_seed(2026)
        cls.x=np.random.default_rng(91).integers(0,256,(16,28,28),dtype=np.uint8)
        cls.x[0]=0;cls.x[1]=255;cls.models={}
        for mode in ('int8','v25h'):
            m=V25DASH(mode);m.calibrate(torch.from_numpy(cls.x.copy()).float()[:,None]/256)
            cls.models[mode]=m

    def test_49_transform_matches_independent_spatial_5x5(self):
        rng=np.random.default_rng(2026)
        for _ in range(128):
            x=rng.integers(0,256,(6,6),dtype=np.int64);w=rng.integers(-128,128,(5,5),dtype=np.int64)
            actual=inverse((BM@x.ravel())*(GM@w.ravel()))
            expected=[np.sum(x[r:r+5,c:c+5]*w) for r in range(2) for c in range(2)]
            np.testing.assert_array_equal(actual,expected)

    def test_frozen_v25_source_transform_parity(self):
        path=Path(__file__).resolve().parents[1]/'source_v25h/explore_v25.py'
        spec=importlib.util.spec_from_file_location('frozen_v25',path)
        source=importlib.util.module_from_spec(spec);sys.modules[spec.name]=source;spec.loader.exec_module(source)
        np.testing.assert_array_equal(BM,source.B_MAT)
        np.testing.assert_array_equal(GM,source.G_MAT)
        np.testing.assert_array_equal(LANE_BW8,source.LANE_BW_BASE)
        # Compare arbitrary coded products, including negative non-divisible inverse sums.
        p=np.random.default_rng(71).integers(-100000,100000,(128,49),dtype=np.int64)
        np.testing.assert_array_equal(inverse(p),source.inverse_pfdw(p))

    def test_rne_negative_and_positive_ties(self):
        x=np.arange(-255,256,dtype=np.int64)
        for s in range(9):np.testing.assert_array_equal(rne(x,s),np.rint(x/2**s))

    def test_full_network_qat_integer_backend_equivalence(self):
        for m in self.models.values():crosscheck(m,self.x,'cpu')

    def test_coded_coefficients_and_shift_terms(self):
        for bits in (5,6,9):
            x=np.arange(-(1<<(bits-1)),1<<(bits-1))
            for scheme in ('pot1','sp2'):
                q,t=quantize(x,bits,scheme);single_terms(t)
                np.testing.assert_array_equal(t.sum(-1),q)
                if scheme=='pot1':single_terms(q)
                np.testing.assert_array_equal(shift_products(np.full_like(t,255),t).sum(-1),255*q)
        # A direct spatial convolution ceases to be the correct golden once G coefficients are coded.
        with self.assertRaises(ValueError):infer_spatial(self.x,self.models['v25h'].export_integer())

    def test_export_roundtrip_and_contract_rejections(self):
        for mode,m in self.models.items():
            p=m.export_integer();self.assertEqual(range_report(p)['status'],'PASS_FULL_U8_INTERVAL_BOUNDS')
            with tempfile.TemporaryDirectory() as td:
                export(p,td);q=load(Path(td)/'weights_int.npz')
                for key in p:np.testing.assert_array_equal(p[key],q[key])
            bad=copy.deepcopy(p)
            if mode=='v25h':bad['q1_td'][0,0,0]=3
            else:bad['q1_td'][0,0,0]+=3
            with self.assertRaises(ValueError):validate(bad)
            bad=copy.deepcopy(p);bad['bfc'][0]=(1<<31)-1
            with self.assertRaises(OverflowError):range_report(bad)
            if mode=='v25h':
                rtl,_=generate_engine(p,'shift')
                # The generated coefficient datapath contains no generic multiply.
                self.assertNotRegex(rtl,r'p3_\d+\s*<=.*\*')

    def test_training_gradients_through_transformed_coding(self):
        m=self.models['v25h'];m.zero_grad(set_to_none=True)
        y=torch.tensor(np.arange(len(self.x))%4,dtype=torch.long)
        loss=torch.nn.functional.cross_entropy(m(torch.from_numpy(self.x.copy()).float()[:,None]/256),y)
        loss.backward()
        for p in m.parameters():self.assertIsNotNone(p.grad);self.assertTrue(torch.isfinite(p.grad).all())

if __name__=='__main__':unittest.main()
