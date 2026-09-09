import importlib.util
import json
import pathlib
import tempfile
import time
import unittest
import uuid

HERE = pathlib.Path(__file__).parent

def load(name):
    spec=importlib.util.spec_from_file_location(name,HERE/(name+'.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

operator=load('call_diagnostics')
monitor=load('monitor_call_diagnostics')

class CallMonitorTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=pathlib.Path(self.temp.name);self.store=self.root/'store';self.store.mkdir()
        self.output=self.root/'report'/'latest.json';self.now=int(time.time()*1000)
        self.trace=str(uuid.uuid4());self.path=self.store/(self.trace+'.json')
        self.created=self.now-1000

    def record(self,count,**changes):
        record={'createdAtMs':self.created,'dropAccountingVersion':1,'dropped':count,
                'events':[],'summaries':{},'owner':'SECRET_OWNER','participants':['SECRET_PARTICIPANT']}
        record.update(changes);self.path.write_text(json.dumps(record))

    def tick(self,**kwargs):
        return monitor.run_tick(operator,self.store,self.output,self.now,**kwargs)

    def test_first_positive_stable_increase_and_coverage_remain_separate(self):
        self.record(5)
        first,_=self.tick()
        self.assertIn('diagnostic_evidence_incomplete',first['alerts'])
        self.assertNotIn('telemetry_loss_observed',first['alerts'])
        self.assertIsNone(first['loss']['observedInterval']['newDroppedEvents'])
        self.now+=300000
        stable,change=self.tick()
        self.assertIsNone(change)
        self.assertEqual(stable['loss']['observedInterval']['newDroppedEvents'],0)
        self.record(8);self.now+=300000
        increased,change=self.tick()
        self.assertEqual(increased['loss']['observedInterval']['observedIncreaseLowerBound'],3)
        self.assertIn('telemetry_loss_observed',change['active'])
        self.now+=300000
        stable,change=self.tick()
        self.assertIn('telemetry_loss_observed',change['cleared'])
        self.assertIn('diagnostic_evidence_incomplete',stable['alerts'])
        self.assertEqual(stable['counts']['droppedEvents'],8)

    def test_record_generation_reset_and_removal_are_unknown(self):
        self.record(5);self.tick();self.now+=1000
        self.created+=1;self.record(20)
        generation,_=self.tick()
        self.assertIsNone(generation['loss']['observedInterval']['newDroppedEvents'])
        self.assertEqual(generation['loss']['observedInterval']['missingCounters'],1)
        self.record(1);self.now+=1000
        reset,_=self.tick()
        self.assertEqual(reset['loss']['observedInterval']['resetCounters'],1)
        self.assertNotIn('telemetry_loss_observed',reset['alerts'])
        self.path.unlink();self.now+=1000
        missing,_=self.tick()
        self.assertIsNone(missing['loss']['observedInterval']['newDroppedEvents'])
        self.assertEqual(missing['loss']['observedInterval']['missingCounters'],1)

    def test_state_private_atomic_and_snapshot_failure_does_not_advance(self):
        self.record(3);self.tick()
        state=self.output.parent/'state.json';prior=state.read_bytes()
        for path in (self.output,state):
            self.assertEqual(path.stat().st_mode&0o777,0o600)
            self.assertNotIn('SECRET',path.read_text())
            self.assertNotIn(self.trace,path.read_text())
        self.assertEqual(self.output.parent.stat().st_mode&0o777,0o700)
        self.record(4);self.now+=1000
        def fail(path,value):
            if path==self.output:raise OSError('SECRET_PATH')
            monitor.atomic_write(path,value)
        with self.assertRaises(OSError):self.tick(writer=fail)
        self.assertEqual(state.read_bytes(),prior)
        retried,_=self.tick()
        self.assertEqual(retried['loss']['observedInterval']['observedIncreaseLowerBound'],1)
        self.assertFalse(any(p.name.startswith('.call-monitor-') for p in self.output.parent.iterdir()))

    def test_corrupt_or_old_state_has_no_comparable_baseline(self):
        self.record(3);self.tick()
        state=self.output.parent/'state.json'
        state.write_text('SECRET invalid')
        result,_=self.tick()
        self.assertIsNone(result['loss']['observedInterval']['newDroppedEvents'])
        self.assertNotIn('SECRET',state.read_text())
        self.now+=15*86400000
        result,_=self.tick()
        self.assertFalse(result['loss']['observedInterval']['baselineAvailable'])

    def test_saturated_stable_ledger_does_not_claim_zero_actual_loss(self):
        self.record(3,discardLedgerSaturated=True);self.tick();self.now+=1000
        result,_=self.tick()
        self.assertIsNone(result['loss']['observedInterval']['newDroppedEvents'])
        self.assertEqual(result['loss']['observedInterval']['observedIncreaseLowerBound'],0)
        self.assertIsNone(result['rates']['telemetry_loss']['rate'])
        self.assertIn('diagnostic_evidence_incomplete',result['alerts'])

if __name__=='__main__':unittest.main()
