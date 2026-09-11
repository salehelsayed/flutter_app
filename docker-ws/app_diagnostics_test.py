import importlib.util
import hashlib
import json
import pathlib
import tempfile
import time
import unittest
import uuid

SPEC = importlib.util.spec_from_file_location('app_diagnostics', pathlib.Path(__file__).with_name('app_diagnostics.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

class AppDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = pathlib.Path(self.temp.name)
        self.now = int(time.time()*1000)
        self.owner = 'a'*64
        self.consent = {self.owner:{'consentEpoch':1,'enabled':True,'updatedAtMs':self.now}}
        self.write_consent()
        self.count = 0

    def write_consent(self):
        (self.directory/'consent.json').write_text(json.dumps(self.consent))

    def event(self, **changes):
        e = {'schemaVersion':1,'eventId':str(uuid.uuid4()),'runId':str(uuid.uuid4()),'traceId':str(uuid.uuid4()),'attemptId':str(uuid.uuid4()),'sequence':0,'occurredAtMs':self.now,'elapsedMs':0,'feature':'private_media','stage':'start','outcome':'started','reason':'none','source':'flutter','build':'1.0.1+112','platform':'ios','values':{}}
        e.update(changes)
        return e

    def record(self, events, owner=None, **changes):
        self.count += 1
        data = {'ownerDigest':owner or self.owner,'consentEpoch':1,'createdAtMs':self.now,'events':[{'receivedAtMs':self.now,'event':e} for e in events if e['stage'] not in MODULE.FINAL],'finals':{str(i):{'receivedAtMs':self.now,'event':e} for i,e in enumerate(events) if e['stage'] in MODULE.FINAL},'dropped':0}
        data.update(changes)
        (self.directory/(format(self.count,'064x')+'.json')).write_text(json.dumps(data))

    def test_schema_matches_canonical_and_rejects_free_text(self):
        canonical = pathlib.Path(__file__).resolve().parents[1]/'tool/app_diagnostics/schema_v1.json'
        self.assertEqual(MODULE.SCHEMA,json.loads(canonical.read_text()))
        e = self.event()
        self.assertTrue(MODULE.validate(e))
        for key,value in [('reason','my secret exception'),('source','relay'),('attemptId',str(uuid.uuid1())),('build','a'*81),('values',{'privatePath':'secret'}),('values',{'count':True})]:
            bad = dict(e);bad[key]=value
            self.assertFalse(MODULE.validate(bad))
        e['values']={'fingerprint':'a'*64,'operation':'peer_dial','reportTimeIsIntervalEnd':True,'extensionProcess':True}
        self.assertTrue(MODULE.validate(e))
        with self.assertRaises(ValueError):MODULE.decode('{"key":1,"key":2}')

    def test_failed_then_success_retry_and_owner_partition(self):
        start = self.event()
        failure = dict(start,eventId=str(uuid.uuid4()),sequence=1,stage='finish',outcome='failed',reason='hash_mismatch')
        retry = dict(start,eventId=str(uuid.uuid4()),attemptId=str(uuid.uuid4()))
        success = dict(retry,eventId=str(uuid.uuid4()),sequence=1,stage='finish',outcome='success')
        self.record([start,failure]);self.record([retry,success])
        other='b'*64;self.consent[other]=self.consent[self.owner];self.write_consent();self.record([start],owner=other)
        result=MODULE.report(self.directory,trace=start['traceId'],now_ms=self.now)
        self.assertEqual(result['attemptsObserved'],3)
        self.assertEqual(sorted(a['outcome'] for a in result['attempts']),['failed','incomplete','success'])
        self.assertEqual(result['groups'][0]['technicalRateDenominator'],2)
        self.assertEqual(result['groups'][0]['missingFinal'],1)
        raw=json.dumps(result)
        self.assertNotIn(self.owner,raw);self.assertNotIn(other,raw);self.assertNotIn('ownerDigest',raw)
        self.assertEqual(len({a['endpointAlias'] for a in result['attempts']}),2)

    def test_minimum_rate_denominator_and_expected_exclusions(self):
        for outcome in ['failed','failed','success','success','canceled','blocked','expired']:
            e=self.event();self.record([e,dict(e,eventId=str(uuid.uuid4()),stage='finish',outcome=outcome,reason='none',sequence=1)])
        report=MODULE.report(self.directory,now_ms=self.now)
        self.assertEqual(report['groups'][0]['technicalRateDenominator'],4)
        self.assertFalse(any(a['kind']=='technical_failure_rate' for a in report['alerts']))
        e=self.event();self.record([e,dict(e,eventId=str(uuid.uuid4()),stage='finish',outcome='success',sequence=1)])
        report=MODULE.report(self.directory,now_ms=self.now)
        alert=next(a for a in report['alerts'] if a['kind']=='technical_failure_rate')
        self.assertEqual(alert['denominator'],5);self.assertEqual(alert['count'],2)

    def test_erased_expired_invalid_and_loss(self):
        e=self.event();self.record([e],dropped=3,discardLedgerSaturated=True)
        self.record([dict(e,eventId=str(uuid.uuid4()),reason='secret')])
        self.record([e],createdAtMs=self.now-15*86400000)
        report=MODULE.report(self.directory,now_ms=self.now)
        self.assertEqual(report['eventReports'],1)
        self.assertEqual(report['health']['invalidEvents'],1)
        self.assertEqual(report['health']['expiredRecords'],1)
        self.assertEqual(report['alerts'][-1]['kind'],'telemetry_coverage_gap')
        self.assertTrue(report['alerts'][-1]['lossCountIsLowerBound'])
        self.consent[self.owner]['erasePending']=True;self.write_consent()
        self.assertEqual(MODULE.report(self.directory,now_ms=self.now)['eventReports'],0)
        self.consent[self.owner]['erasePending']=False;self.consent[self.owner]['consentEpoch']=2;self.write_consent()
        self.assertEqual(MODULE.report(self.directory,now_ms=self.now)['eventReports'],0)

    def test_support_code_joins_imported_native_original_run(self):
        code=str(uuid.uuid4())
        e=self.event(source='ios',feature='runtime',stage='crash',outcome='failed',reason='os_crash',reportingRunId=code)
        self.record([e])
        self.assertEqual(MODULE.report(self.directory,support_code=code,now_ms=self.now)['eventReports'],1)
        self.assertEqual(MODULE.report(self.directory,run=code,now_ms=self.now)['eventReports'],1)
        self.assertEqual(MODULE.report(self.directory,support_code=e['traceId'],now_ms=self.now)['eventReports'],1)
        self.assertEqual(MODULE.report(self.directory,trace=code,now_ms=self.now)['eventReports'],0)

    def test_restart_terminal_joins_same_attempt_across_runs(self):
        start=self.event(sequence=20)
        finish=dict(start,eventId=str(uuid.uuid4()),runId=str(uuid.uuid4()),sequence=1,stage='finish',outcome='interrupted_unknown',reason='interrupted_before_final_record',elapsedMs=3)
        self.record([start]);self.record([finish])
        result=MODULE.report(self.directory,support_code=finish['runId'],now_ms=self.now)
        self.assertEqual(result['attemptsObserved'],1)
        attempt=result['attempts'][0]
        self.assertTrue(attempt['startObserved']);self.assertTrue(attempt['finalObserved'])
        self.assertEqual(attempt['outcome'],'interrupted_unknown')
        self.assertEqual(attempt['completeness'],'start_and_final')
        self.assertTrue(attempt['crossRunRecovery']);self.assertIsNone(attempt['durationMs'])
        self.assertEqual(set(attempt['runIds']),{start['runId'],finish['runId']})
        self.assertEqual(result['eventReports'],2)

    def test_unknown_interruption_is_outside_technical_rate(self):
        e=self.event(stage='finish',outcome='interrupted_unknown',reason='interrupted_before_final_record')
        self.record([e])
        report=MODULE.report(self.directory,now_ms=self.now)
        self.assertEqual(report['groups'][0]['technicalRateDenominator'],0)
        self.assertEqual(report['groups'][0]['outcomes']['interrupted_unknown'],1)

    def test_unscoped_health_and_storage_failure_are_observations_not_attempts(self):
        health=self.event(feature='runtime',stage='snapshot',outcome='ok')
        failure=self.event(feature='storage',stage='commit',outcome='failed',reason='storage_failed')
        for event in [health,failure]:
            event.pop('attemptId');event.pop('traceId')
            self.record([event])
        result=MODULE.report(self.directory,now_ms=self.now)
        self.assertEqual(result['eventReports'],2)
        self.assertEqual(result['attemptsObserved'],0)
        self.assertEqual(result['groups'],[])
        self.assertFalse(any(a['kind'] in ['missing_final_rate','missing_start_rate','technical_failure_rate'] for a in result['alerts']))
        self.assertEqual(result['errors'][0]['reason'],'storage_failed')

    def test_old_client_snapshot_retains_gap_without_current_window_loss(self):
        event=self.event(feature='runtime',stage='snapshot',outcome='ok',values={'droppedEvents':5})
        self.record([event])
        result=MODULE.report(self.directory,hours=1,now_ms=self.now+2*3600000)
        self.assertEqual(result['eventReports'],0)
        self.assertEqual(result['health']['clientReportedDroppedEvents'],5)
        self.assertTrue(result['evidenceIncomplete'])
        self.assertIsNone(result['loss']['window']['newDroppedEvents'])
        self.assertNotIn('telemetry_loss',[a['kind'] for a in result['alerts']])

    def test_client_reported_loss_remains_distinct_from_server_loss(self):
        self.record([self.event(feature='runtime',stage='snapshot',outcome='ok',values={'droppedEvents':4})])
        result=MODULE.report(self.directory,now_ms=self.now)
        self.assertEqual(result['health']['clientReportedDroppedEvents'],4)
        alert=next(a for a in result['alerts'] if a['kind']=='telemetry_coverage_gap')
        self.assertEqual(alert['clientReportedDroppedEvents'],4)
        self.assertEqual(alert['droppedEvents'],0)

    def test_new_error_and_static_dashboard_are_sanitized(self):
        for _ in range(3):
            e=self.event(stage='finish',outcome='failed',reason='hash_mismatch',values={'fingerprint':'f'*64});self.record([e])
        report=MODULE.report(self.directory,now_ms=self.now)
        self.assertTrue(any(a['kind']=='new_error_signature' for a in report['alerts']))
        dashboard=MODULE.dashboard(report)
        self.assertIn('App diagnostics',dashboard);self.assertNotIn(self.owner,dashboard)
        self.assertNotIn('<script',dashboard)

    def test_class_only_fingerprints_are_explicit_and_preserve_error_classes(self):
        for kind in ['platform', 'state']:
            for values in [{'errorClass':kind}, {'errorClass':kind,'fingerprint':hashlib.sha256((kind+'|').encode()).hexdigest()}]:
                self.record([self.event(feature='runtime',stage='process',outcome='failed',reason='unhandled_error',values=values)])
        result=MODULE.report(self.directory,now_ms=self.now)
        self.assertEqual(len(result['errors']),2)
        self.assertEqual({e['errorClass'] for e in result['errors']},{'platform','state'})
        for error in result['errors']:
            self.assertIsNone(error['fingerprint'])
            self.assertEqual(error['fingerprintSpecificity'],'class_only')
            self.assertEqual(error['eventReports'],2)

    def test_native_error_codes_are_distinct_without_inventing_fingerprints(self):
        for code in [1, 2]:
            for _ in range(3):
                self.record([self.event(feature='push',stage='presentation',outcome='failed',reason='prepare_failed',values={'errorClass':'platform','osReasonCode':code})])
        result=MODULE.report(self.directory,now_ms=self.now)
        self.assertEqual(len(result['errors']),2)
        self.assertEqual({e['osReasonCode'] for e in result['errors']},{1,2})
        self.assertTrue(all(e['eventReports']==3 and e['fingerprint'] is None for e in result['errors']))
        self.assertEqual({a['osReasonCode'] for a in result['alerts'] if a['kind']=='new_error_signature'},{1,2})

    def test_legacy_class_only_baseline_does_not_become_a_new_error(self):
        old=self.event(feature='runtime',stage='process',outcome='failed',reason='unhandled_error',values={'errorClass':'platform','fingerprint':hashlib.sha256(b'platform|').hexdigest()})
        self.record([old])
        path=self.directory/(format(self.count,'064x')+'.json')
        record=json.loads(path.read_text())
        record['events'][0]['receivedAtMs']=self.now-2*3600000
        path.write_text(json.dumps(record))
        for _ in range(3):
            self.record([self.event(feature='runtime',stage='process',outcome='failed',reason='unhandled_error',values={'errorClass':'platform'})])
        result=MODULE.report(self.directory,hours=1,now_ms=self.now)
        self.assertEqual(len(result['errors']),1)
        self.assertFalse(result['errors'][0]['newInRetainedBaseline'])
        self.assertFalse(any(a['kind']=='new_error_signature' for a in result['alerts']))

if __name__=='__main__':unittest.main()
