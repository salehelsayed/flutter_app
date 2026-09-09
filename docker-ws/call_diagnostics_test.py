import importlib.util
import json
import pathlib
import tempfile
import time
import unittest
import uuid

spec = importlib.util.spec_from_file_location('call_diagnostics', pathlib.Path(__file__).with_name('call_diagnostics.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CallDiagnosticsOperatorTests(unittest.TestCase):
    def event(self, trace, role='caller', source='flutter', action='finish', media=True):
        return {'schemaVersion': 1, 'eventId': str(uuid.uuid4()), 'traceId': trace, 'source': source, 'role': role, 'runId': str(uuid.uuid4()), 'sequence': 1, 'occurredAtMs': int(time.time()*1000), 'elapsedMs': 1, 'stage': 'terminal' if action == 'finish' else 'signaling', 'action': action, 'outcome': 'completed_after_media' if media else 'ok', 'reason': 'none', 'values': {'mediaFlowVerified': media}}

    def test_historical_counter_is_not_a_current_window_loss_rate(self):
        event=self.event(str(uuid.uuid4()))
        output=module.report([{'events':[{'receivedAtMs':1,'event':event}],'droppedEvents':500}],0)
        self.assertTrue(output['evidenceIncomplete'])
        self.assertIsNone(output['rates']['telemetry_loss']['rate'])
        self.assertNotIn('telemetry_loss_high',output['alerts'])
        self.assertEqual(output['loss']['retainedLifetime']['droppedEvents'],500)

    def test_counter_interval_handles_population_swap_retention_reset_and_first_sample(self):
        current={'a':{'count':5,'lowerBound':False}}
        first,_=module.counter_interval(current,{},1000)
        self.assertIsNone(first['newDroppedEvents'])
        _,baseline=module.counter_interval(current,{},1000)
        stable,_=module.counter_interval(current,baseline,2000)
        self.assertEqual(stable['observedIncreaseLowerBound'],0)
        increased,_=module.counter_interval({'a':{'count':7,'lowerBound':False}},baseline,2000)
        self.assertEqual(increased['observedIncreaseLowerBound'],2)
        swapped,_=module.counter_interval({'b':{'count':7,'lowerBound':False}},baseline,2000)
        self.assertIsNone(swapped['newDroppedEvents'])
        self.assertEqual(swapped['missingCounters'],1)
        reset,_=module.counter_interval({'a':{'count':1,'lowerBound':False}},baseline,2000)
        self.assertEqual(reset['resetCounters'],1)
        stale,_=module.counter_interval(current,baseline,1000+15*86400000)
        self.assertIsNone(stale['newDroppedEvents'])

    def test_window_loss_requires_exact_counter_timestamp_placement(self):
        def project(first=None, updated=None, saturated=False, legacy=0):
            row={'events':[], 'droppedEvents':10, 'discardLedgerSaturated':saturated,
                 'legacyQuotaRejectionAttempts':legacy}
            if first is not None: row['droppedFirstAtMs']=first
            if updated is not None: row['droppedUpdatedAtMs']=updated
            return module.report([row],0,since_ms=100,now_ms=200)
        self.assertEqual(project(110,150)['loss']['window']['droppedEvents'],10)
        self.assertIn('telemetry_loss_high',project(110,150)['alerts'])
        before=project(10,50)
        self.assertEqual(before['loss']['window']['droppedEvents'],0)
        self.assertTrue(before['evidenceIncomplete'])
        self.assertNotIn('telemetry_loss_high',before['alerts'])
        for result in [project(10,150),project(None,150),project(110,150,True),project(110,150,legacy=1)]:
            self.assertIsNone(result['loss']['window']['droppedEvents'])
            self.assertTrue(result['evidenceIncomplete'])
            self.assertNotIn('telemetry_loss_high',result['alerts'])
        # Invalid records are not event counts and never become a loss rate.
        bad=module.report([],100,since_ms=100,now_ms=200)
        self.assertTrue(bad['evidenceIncomplete'])
        self.assertNotIn('telemetry_loss_high',bad['alerts'])

    def test_runtime_v5_and_loss_outside_event_window_remain_readable(self):
        now=int(time.time()*1000)
        with tempfile.TemporaryDirectory() as folder:
            path=pathlib.Path(folder)
            for name in [str(uuid.uuid5(uuid.NAMESPACE_URL,'legacy')),str(uuid.uuid4()),'a'*64]:
                event=self.event(str(uuid.uuid4()))
                record={'createdAtMs':now-10000,'dropAccountingVersion':1,'dropped':4,
                        'droppedFirstAtMs':now-9000,'droppedUpdatedAtMs':now-8000,
                        'events':[{'event':event,'receivedAtMs':now-9000}], 'summaries':{}}
                (path/('runtime-'+name+'.json')).write_text(json.dumps(record))
            samples={}
            rows,rejected=module.read_records(path,now-1000,now_ms=now,_loss_samples=samples)
            self.assertEqual(rejected,0); self.assertEqual(len(rows),3)
            self.assertTrue(all(not row['events'] for row in rows))
            result=module.report(rows,rejected)
            self.assertEqual(result['counts']['droppedEvents'],12)
            self.assertEqual(result['loss']['window']['droppedEvents'],0)
            self.assertTrue(result['evidenceIncomplete'])
            self.assertEqual(len(samples),3)
            self.assertTrue(all(len(key)==64 for key in samples))
            invalid=self.event(str(uuid.uuid4()));invalid['runId']=str(uuid.uuid5(uuid.NAMESPACE_URL,'not-a-run'))
            self.assertFalse(module.valid_event(invalid))

    def test_interval_saturation_caps_and_clock_rollback_stay_unknown(self):
        _,prior=module.counter_interval({'a':{'count':5,'lowerBound':True}}, {},1000)
        interval,_=module.counter_interval({'a':{'count':5,'lowerBound':True}},prior,2000)
        self.assertIsNone(interval['newDroppedEvents']);self.assertEqual(interval['observedIncreaseLowerBound'],0)
        interval,_=module.counter_interval({'a':{'count':6,'lowerBound':True}},prior,2000)
        self.assertEqual(interval['observedIncreaseLowerBound'],1);self.assertIsNone(interval['newDroppedEvents'])
        interval,_=module.counter_interval({'a':{'count':6,'lowerBound':False}},prior,999)
        self.assertFalse(interval['baselineAvailable'])
        values={str(i):{'count':1,'lowerBound':False} for i in range(module.MAX_LOSS_COUNTERS+1)}
        interval,next_state=module.counter_interval(values,{},2000)
        self.assertTrue(interval['baselineTruncated']);self.assertEqual(len(next_state['counters']),module.MAX_LOSS_COUNTERS)

    def test_endpoint_completeness_does_not_promote_one_sided_media_or_ack(self):
        trace = str(uuid.uuid4())
        events = [self.event(trace), self.event(trace, role='server', source='relay', action='ack', media=False)]
        rows = [{'events': [{'receivedAtMs': int(time.time()*1000), 'event': e} for e in events], 'droppedEvents': 0}]
        output = module.report(rows, 0, trace)
        self.assertEqual(output['mailboxAdmittedTraceCount'], 0)
        self.assertEqual(output['anyEndpointReportedMediaTraceCount'], 1)
        self.assertEqual(output['bothEndpointsReportedMediaTraceCount'], 0)
        self.assertEqual(output['missingEndpointTerminalTraceCount'], 1)
        self.assertFalse(output['endpointCompleteness']['calleeTerminal'])
        rows[0]['events'].append({'receivedAtMs': int(time.time()*1000), 'event': self.event(trace, role='callee', source='android')})
        output = module.report(rows, 0, trace)
        self.assertEqual(output['bothEndpointsReportedMediaTraceCount'], 1)
        self.assertEqual(output['bothEndpointsTerminalTraceCount'], 1)

    def test_projection_excludes_private_maps_and_rejects_extra_event_fields(self):
        trace = str(uuid.uuid4())
        valid = self.event(trace)
        invalid = self.event(trace)
        invalid['token'] = 'private-canary'
        now = int(time.time()*1000)
        record = {'owner': 'private-canary', 'participants': ['private-canary'], 'bindings': ['private-canary'], 'createdAtMs': now, 'events': [{'receivedAtMs': now, 'event': e} for e in [valid, invalid]], 'summaries': {}, 'dropped': 0}
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            (path / (trace+'.json')).write_text(json.dumps(record))
            (path / 'private.json').write_text(json.dumps({'token': 'private-canary'}))
            rows, rejected = module.read_records(path, now-1000, trace)
            output = module.report(rows, rejected, trace)
        self.assertEqual(rejected, 1)
        self.assertNotIn('private-canary', json.dumps(output))
        self.assertEqual(len(output['events']), 1)

    def test_schema_fixture_and_uuid_build_bounds(self):
        schema = pathlib.Path(__file__).resolve().parents[1] / 'tool/call_diagnostics/schema_v1.json'
        self.assertEqual(module.SCHEMA, json.loads(schema.read_text()))
        event = self.event(str(uuid.uuid4()))
        self.assertTrue(module.valid_event(event))
        event['eventId'] = str(uuid.uuid1())
        self.assertFalse(module.valid_event(event))
        event['eventId'] = str(uuid.uuid4())
        event['build'] = 'a'*81
        self.assertFalse(module.valid_event(event))

    def test_joined_record_bound_and_legacy_loss_are_projected_without_private_ledger(self):
        now = int(time.time()*1000)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            for modern in (False, True):
                trace = str(uuid.uuid4())
                record = {'createdAtMs': now, 'events': [{'receivedAtMs': now, 'event': self.event(trace)}],
                          'summaries': {}, 'dropped': 3 if modern else 742,
                          'discardedEventIds': ['private-canary'], 'privatePadding': 'x'*140000}
                if modern:
                    record.update(dropAccountingVersion=1, discardLedgerSaturated=True)
                target = path/(trace+'.json')
                target.write_text(json.dumps(record))
                self.assertGreater(target.stat().st_size, 128*1024)
                self.assertLess(target.stat().st_size, module.MAX_RECORD_BYTES)
            rows, rejected = module.read_records(path, now-1000)
            output = module.report(rows, rejected)
        self.assertEqual(rejected, 0)
        self.assertEqual(output['counts']['droppedEvents'], 3)
        self.assertEqual(output['counts']['legacyQuotaRejectionAttempts'], 742)
        self.assertEqual(output['counts']['recordsWithUnknownHistoricalLoss'], 1)
        self.assertEqual(output['counts']['discardLedgerSaturatedRecords'], 1)
        self.assertFalse(output['telemetryLossCountExact'])
        self.assertTrue(output['rates']['telemetry_loss']['rateIsLowerBound'])
        self.assertTrue(output['evidenceIncomplete'])
        self.assertNotIn('private-canary', json.dumps(output))
        self.assertNotIn('discardedEventIds', json.dumps(output))

    def test_alert_minimum_samples_and_neutral_terminal_exclusion(self):
        rows = []
        for i in range(5):
            e = self.event(str(uuid.uuid4()), media=False)
            e['outcome'] = 'signaling_failed'
            rows.append({'events': [{'receivedAtMs': i+1, 'event': e}], 'droppedEvents': 0})
        small = module.report(rows[:4], 0)
        self.assertNotIn('technical_setup_failure_high', small['alerts'])
        large = module.report(rows, 0)
        self.assertIn('technical_setup_failure_high', large['alerts'])
        neutral = self.event(str(uuid.uuid4()), media=False)
        neutral['outcome'] = 'declined'
        rows.append({'events': [{'receivedAtMs': 6, 'event': neutral}], 'droppedEvents': 0})
        with_neutral = module.report(rows, 0)
        self.assertEqual(with_neutral['rates']['technical_setup_failure']['denominator'], 5)
        self.assertEqual(with_neutral['neutralTerminalTraceCount'], 1)
        for category in ('preflight_rejection', 'answered_without_verified_media', 'drop_after_media', 'provider_failure', 'credential_failure', 'telemetry_loss', 'cleanup_failure', 'withdrawal_unknown_origin'):
            self.assertIn(category, with_neutral['rates'])

    def test_terminal_only_preflight_failure_has_its_own_honest_denominator(self):
        # Real offline-producer shape: attempt/start followed immediately by
        # terminal/preflight_failed, without a separate preflight-stage event.
        trace = str(uuid.uuid4())
        start = self.event(trace, action='start', media=False)
        start.update(stage='attempt', outcome='started', values={}, sequence=7)
        terminal = dict(start, eventId=str(uuid.uuid4()), sequence=8,
                        stage='terminal', action='finish',
                        outcome='preflight_failed', reason='graph_unavailable',
                        values={'terminal': True})
        rows = [{'events': [{'receivedAtMs': i+1, 'event': event}
                            for i, event in enumerate((start, terminal))],
                 'droppedEvents': 0}]
        self.assertTrue(all(module.valid_event(e) for e in (start, terminal)))
        output = module.report(rows, 0, trace)
        self.assertEqual(output['rates']['preflight_rejection']['numerator'], 1)
        self.assertEqual(output['rates']['preflight_rejection']['denominator'], 1)
        self.assertEqual(output['rates']['technical_setup_failure']['numerator'], 0)
        self.assertEqual(output['rates']['technical_setup_failure']['denominator'], 0)
        self.assertIsNone(output['rates']['technical_setup_failure']['rate'])
        self.assertEqual(output['firstReceivedFailure']['reason'], 'graph_unavailable')
        self.assertFalse(output['rates']['preflight_rejection']['alertEligible'])
        self.assertEqual(output['mailboxAdmittedTraceCount'], 0)
        self.assertEqual(output['anyEndpointReportedMediaTraceCount'], 0)

        # Duplicate phase/terminal evidence must not count the same attempt twice.
        phase = dict(terminal, eventId=str(uuid.uuid4()), stage='preflight',
                     action='check', outcome='rejected')
        rows[0]['events'].append({'receivedAtMs': 3, 'event': phase})
        for i, outcome in enumerate(('completed_after_media', 'signaling_failed', 'declined')):
            event = self.event(str(uuid.uuid4()), media=False)
            event.update(outcome=outcome)
            rows.append({'events': [{'receivedAtMs': i+4, 'event': event}],
                         'droppedEvents': 0})
        mixed = module.report(rows, 0)
        self.assertEqual(mixed['rates']['preflight_rejection']['numerator'], 1)
        self.assertEqual(mixed['rates']['preflight_rejection']['denominator'], 4)
        self.assertEqual(mixed['rates']['technical_setup_failure']['numerator'], 1)
        self.assertEqual(mixed['rates']['technical_setup_failure']['denominator'], 2)
        self.assertEqual(mixed['neutralTerminalTraceCount'], 1)

    def test_trace_lookup_joins_only_referenced_authority_operations(self):
        trace, operation = str(uuid.uuid4()), str(uuid.uuid4())
        call = self.event(trace)
        call['parentOperationId'] = operation
        authority = self.event(str(uuid.uuid4()), role='local', source='ios', action='invalidate', media=False)
        del authority['traceId']
        authority['stage'] = 'authority'
        authority['operationId'] = operation
        authority['reason'] = 'pushkit_token_invalidated'
        now = int(time.time()*1000)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            for name, event in [(trace, call), ('runtime-'+authority['runId'], authority)]:
                (path/(name+'.json')).write_text(json.dumps({'createdAtMs': now, 'events': [{'receivedAtMs': now, 'event': event}], 'summaries': {}}))
            rows, rejected = module.read_records(path, now-1000, trace)
            output = module.report(rows, rejected, trace)
            module.attach_authority_chain(output, path, now-1000, 1000)
        self.assertEqual(output['unresolvedOperationReferenceCount'], 0)
        self.assertEqual(output['relatedAuthorityOperations'][0]['reason'], 'pushkit_token_invalidated')

    def test_native_only_admission_failure_retains_disposition_and_custody(self):
        trace = str(uuid.uuid4())
        event = self.event(trace, role='callee', source='android', media=False)
        event.update(stage='admission', outcome='failed', reason='backend_unavailable',
                     values={'admissionDisposition': 'deferred', 'databaseClosed': True,
                             'leaseReleased': True, 'requiredPersistenceComplete': False})
        self.assertTrue(module.valid_event(event))
        output = module.report([{'events': [{'receivedAtMs': 1, 'event': event}], 'droppedEvents': 0}], 0, trace)
        self.assertEqual(output['firstReceivedFailure']['stage'], 'admission')
        self.assertEqual(output['firstReceivedFailure']['reason'], 'backend_unavailable')
        self.assertTrue(output['admissionReported'])
        self.assertEqual(output['events'][0]['event']['values']['admissionDisposition'], 'deferred')
        self.assertFalse(output['events'][0]['event']['values']['requiredPersistenceComplete'])
        self.assertEqual(output['mailboxAdmittedTraceCount'], 0)
        self.assertEqual(output['anyEndpointReportedMediaTraceCount'], 0)
        self.assertEqual(output['bothEndpointsTerminalTraceCount'], 0)
        # A push observed on an Android callee, followed by missing admission,
        # places the gap before presentation without requiring it on other paths.
        event.update(stage='push', action='receive', outcome='ok', reason='none', values={})
        missing = module.report([{'events': [{'receivedAtMs': 1, 'event': event}], 'droppedEvents': 0}], 0, trace)
        self.assertLess(missing['missingStageReports'].index('admission'), missing['missingStageReports'].index('presentation'))
        event['source'] = 'ios'
        other = module.report([{'events': [{'receivedAtMs': 1, 'event': event}], 'droppedEvents': 0}], 0, trace)
        self.assertNotIn('admission', other['missingStageReports'])

    def test_all_operational_rate_thresholds_require_minimum_samples(self):
        cases = {
            'preflight_rejection': ('preflight', 'check', 'rejected', 'flutter', 'caller'),
            'answered_without_verified_media': ('terminal', 'finish', 'answered_without_verified_media', 'flutter', 'caller'),
            'drop_after_media': ('terminal', 'finish', 'dropped_after_media', 'flutter', 'caller'),
            'credential_failure': ('turn', 'mint', 'failed', 'relay', 'server'),
            'cleanup_failure': ('cleanup', 'stop', 'failed', 'flutter', 'caller'),
            'withdrawal_unknown_origin': ('authority', 'invalidate', 'ok', 'ios', 'local'),
        }
        for name, (stage, action, outcome, source, role) in cases.items():
            with self.subTest(category=name):
                rows = []
                for i in range(5):
                    event = self.event(str(uuid.uuid4()), source=source, role=role, action=action, media=False)
                    event.update(stage=stage, outcome=outcome)
                    if name == 'withdrawal_unknown_origin':
                        event.update(operationId=str(uuid.uuid4()), reason='unknown')
                    rows.append({'events': [{'receivedAtMs': i+1, 'event': event}], 'droppedEvents': 0})
                self.assertFalse(module.report(rows[:4], 0)['rates'][name]['alertEligible'])
                self.assertIn(name+'_high', module.report(rows, 0)['alerts'])
        provider_rows = []
        for i in range(5):
            trace = str(uuid.uuid4())
            events = []
            for outcome in ('started', 'failed'):
                event = self.event(trace, source='relay', role='server', action='dispatch', media=False)
                event.update(stage='push', outcome=outcome, values={'providerInvoked': True})
                events.append({'receivedAtMs': i+1, 'event': event})
            provider_rows.append({'events': events, 'droppedEvents': 0})
        self.assertNotIn('provider_failure_high', module.report(provider_rows[:4], 0)['alerts'])
        self.assertIn('provider_failure_high', module.report(provider_rows, 0)['alerts'])
        telemetry_rows = [{'events': [{'receivedAtMs': 1, 'event': self.event(str(uuid.uuid4()))}], 'droppedEvents': 1, 'droppedFirstAtMs': 1, 'droppedUpdatedAtMs': 1, '_windowSinceMs': 1, '_windowEndMs': 2} for _ in range(3)]
        self.assertFalse(module.report(telemetry_rows[:1], 0)['rates']['telemetry_loss']['alertEligible'])
        self.assertIn('telemetry_loss_high', module.report(telemetry_rows, 0)['alerts'])


if __name__ == '__main__':
    unittest.main()
