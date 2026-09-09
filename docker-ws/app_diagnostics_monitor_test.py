import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest

HERE=pathlib.Path(__file__).parent
sys.path.insert(0,str(HERE))
import app_diagnostics_monitor as monitor
import app_diagnostics_test as fixtures

class MonitorTests(unittest.TestCase):
    event=fixtures.AppDiagnosticsTests.event
    record=fixtures.AppDiagnosticsTests.record
    write_consent=fixtures.AppDiagnosticsTests.write_consent
    def setUp(self):
        fixtures.AppDiagnosticsTests.setUp(self)
        self.output=self.directory/'monitor'

    def tick(self, now=None, **kwargs):
        return monitor.run_tick(self.directory,self.output,self.now if now is None else now,**kwargs)

    def test_new_error_rate_state_no_repeat_and_clear(self):
        for _ in range(5):
            e=self.event();self.record([e,dict(e,eventId=__import__('uuid').uuid4().__str__(),stage='finish',outcome='failed',reason='hash_mismatch',sequence=1)])
        opened,snapshot=self.tick()
        self.assertTrue(any(a['kind']=='technical_failure_rate' and a['event']=='alert_opened' for a in opened))
        self.assertTrue(any(a['kind']=='new_error_signature' for a in opened))
        self.assertNotIn('attempts',snapshot)
        self.assertEqual(self.tick()[0],[])
        self.consent[self.owner]['enabled']=False;self.write_consent()
        cleared,snapshot=self.tick()
        self.assertTrue(cleared);self.assertTrue(all(a['event']=='alert_cleared' for a in cleared))
        self.assertEqual(snapshot['eventReports'],0)
        self.assertEqual(json.loads((self.output/'state.json').read_text())['active'],{})

    def test_missing_final_alert_has_grace_and_minimum(self):
        for _ in range(5):self.record([self.event()])
        self.assertFalse(any(a['kind']=='missing_final_rate' for a in self.tick()[0]))
        later=self.now+301000
        changes,_=self.tick(later)
        alert=next(a for a in changes if a['kind']=='missing_final_rate')
        self.assertEqual(alert['count'],5);self.assertEqual(alert['denominator'],5)

    def test_atomic_files_are_private_and_state_follows_snapshots(self):
        e=self.event(stage='finish',outcome='failed',reason='io_failed');self.record([e])
        self.tick()
        self.assertEqual(self.output.stat().st_mode&0o777,0o700)
        for name in ['snapshot.json','dashboard.html','alerts.json','state.json']:
            self.assertEqual((self.output/name).stat().st_mode&0o777,0o600)
            self.assertNotIn(self.owner,(self.output/name).read_text())
        prior=(self.output/'state.json').read_bytes()
        def fail(path,raw):
            if path.name=='dashboard.html':raise OSError('SECRET_PATH')
            monitor.atomic_write(path,raw)
        with self.assertRaises(OSError):self.tick(writer=fail)
        self.assertEqual((self.output/'state.json').read_bytes(),prior)
        self.assertFalse(any(p.name.startswith('.app-monitor-') for p in self.output.iterdir()))

    def test_corrupt_state_cannot_export_arbitrary_text(self):
        self.tick()
        (self.output/'state.json').write_text(json.dumps({'schemaVersion':1,'active':{'f'*64:{'kind':'SECRET_KIND','reason':'SECRET_ERROR'}}}))
        changes,_=self.tick()
        self.assertEqual(changes,[])
        self.assertNotIn('SECRET',(self.output/'alerts.json').read_text())

    def test_unreadable_collector_replaces_stale_snapshot_with_explicit_failure(self):
        self.tick()
        def unavailable(*a,**kw):raise OSError('SECRET_PATH')
        changes,snapshot=self.tick(report_fn=unavailable)
        self.assertEqual(snapshot['health']['collectorState'],'unavailable')
        self.assertTrue(any(a['kind']=='collector_unavailable' and a['event']=='alert_opened' for a in changes))
        self.assertNotIn('SECRET',(self.output/'snapshot.json').read_text())
        self.assertTrue(any(a['kind']=='collector_unavailable' and a['event']=='alert_cleared' for a in self.tick()[0]))

    def test_cumulative_loss_first_sample_stable_increment_and_reset(self):
        run='12345678-1234-4123-8123-123456789abc'
        def sample(value):
            self.record([self.event(feature='runtime',stage='snapshot',outcome='ok',runId=run,values={'droppedEvents':value})])
        sample(5)
        _,first=self.tick()
        self.assertTrue(any(a['kind']=='telemetry_coverage_gap' for a in first['alerts']))
        self.assertFalse(any(a['kind']=='telemetry_loss' for a in first['alerts']))
        self.assertIsNone(first['loss']['observedInterval']['newDroppedEvents'])
        self.now+=300000;sample(5)
        _,stable=self.tick()
        self.assertEqual(stable['loss']['observedInterval']['observedCounterIncrements'],0)
        self.assertFalse(any(a['kind']=='telemetry_loss' for a in stable['alerts']))
        self.now+=300000;sample(7)
        _,increased=self.tick()
        self.assertEqual(increased['loss']['observedInterval']['observedCounterIncrements'],2)
        self.assertTrue(any(a['kind']=='telemetry_loss' for a in increased['alerts']))
        self.now+=300000;sample(1)
        _,reset=self.tick()
        self.assertGreater(reset['loss']['observedInterval']['resetCounters'],0)
        self.assertIsNone(reset['loss']['observedInterval']['newDroppedEvents'])

    def test_owner_swap_cannot_cancel_another_counter_increase(self):
        run='12345678-1234-4123-8123-123456789abc'
        other='b'*64
        self.consent[other]={'enabled':True,'consentEpoch':1,'updatedAtMs':self.now};self.write_consent()
        def sample(owner,value):
            self.record([self.event(feature='runtime',stage='snapshot',outcome='ok',runId=run,values={'droppedEvents':value})],owner=owner)
        sample(self.owner,5);sample(other,5);self.tick()
        self.now+=300000;sample(self.owner,8);sample(other,2)
        _,result=self.tick()
        self.assertEqual(result['health']['clientReportedDroppedEvents'],10)
        interval=result['loss']['observedInterval']
        self.assertEqual(interval['observedCounterIncrements'],3)
        self.assertGreater(interval['resetCounters'],0)
        self.assertIsNone(interval['newDroppedEvents'])
        self.assertTrue(any(a['kind']=='telemetry_loss' for a in result['alerts']))
        self.consent[self.owner]['enabled']=False;self.write_consent();self.now+=300000
        _,result=self.tick()
        self.assertGreater(result['loss']['observedInterval']['missingCounters'],0)
        self.assertNotIn(other,json.dumps(result))

    def test_old_snapshot_and_new_run_are_not_fresh_comparable_loss_samples(self):
        run='12345678-1234-4123-8123-123456789abc'
        self.record([self.event(feature='runtime',stage='snapshot',outcome='ok',runId=run,values={'droppedEvents':5})])
        self.tick();self.now+=300000
        _,result=self.tick()
        self.assertGreater(result['loss']['observedInterval']['staleSnapshotCounters'],0)
        self.assertIsNone(result['loss']['observedInterval']['newDroppedEvents'])
        self.record([self.event(feature='runtime',stage='snapshot',outcome='ok',values={'droppedEvents':5})])
        _,result=self.tick()
        self.assertGreater(result['loss']['observedInterval']['firstSeenCounters'],0)
        self.assertEqual(result['loss']['observedInterval']['observedCounterIncrements'],0)
        self.assertFalse(any(a['kind']=='telemetry_loss' for a in result['alerts']))

    def test_client_server_increases_are_not_summed_as_unique_lost_events(self):
        run='12345678-1234-4123-8123-123456789abc'
        sample=self.event(feature='runtime',stage='snapshot',outcome='ok',runId=run,values={'droppedEvents':5})
        self.record([sample],dropped=3);self.tick()
        record_path=next(p for p in self.directory.glob('*.json') if p.name!='consent.json')
        record=json.loads(record_path.read_text());record['dropped']=5;record_path.write_text(json.dumps(record))
        self.now+=300000
        self.record([dict(sample,eventId=__import__('uuid').uuid4().__str__(),values={'droppedEvents':7})])
        _,result=self.tick()
        interval=result['loss']['observedInterval']
        self.assertEqual(interval['byLayer']['client']['observedIncreaseLowerBound'],2)
        self.assertEqual(interval['byLayer']['server']['observedIncreaseLowerBound'],2)
        self.assertEqual(interval['observedCounterIncrements'],4)
        self.assertIsNone(interval['newDroppedEvents'])
        self.assertNotIn('observedIncreaseLowerBound',interval)

    def test_monitor_output_is_bounded(self):
        base=monitor.operator.report(self.directory,now_ms=self.now)
        group={'feature':'media','platform':'ios','build':'1.0.1+112','attemptsObserved':1,'technicalFailures':0,'technicalRateDenominator':1,'missingFinal':0}
        base['groups']=[group]*1000
        base['errors']=[]
        _,snapshot=self.tick(report_fn=lambda *a,**kw:base)
        self.assertEqual(len(snapshot['groups']),monitor.MAX_ENTRIES)
        self.assertEqual(snapshot['groupsTruncated'],800)
        self.assertLess((self.output/'snapshot.json').stat().st_size,monitor.MAX_FILE_BYTES)

if __name__=='__main__':unittest.main()
