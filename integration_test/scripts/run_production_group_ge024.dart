import '../../tool/sims/production_group_ge024_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ge024',
  validatorId: 'validateProductionGroupGe024',
  texts: productionGe024Texts,
  validate: validateProductionGroupGe024,
  steps: (s) async {
    final texts = productionGe024Texts(s.journey.runId);
    String text(String key) => texts[key]!.text;
    String pattern(String key) => RegExp.escape(text(key));
    final name = s.catalogName('ge024');
    await s.createAndAcceptAll(name);
    await s.sendAndReceive(
      'alice',
      'alice-before-parent',
      'aliceGe024BeforeRemovalParent',
      text('aliceGe024BeforeRemovalParent'),
      ['bob', 'charlie'],
    );
    await s.removeCharlie();
    // The removed window starts once the remaining pair holds the new key.
    await s.rotatedForRemainingPair();
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    await s.sendAndReceive(
      'alice',
      'alice-removed-parent',
      'aliceGe024RemovedWindowParent',
      text('aliceGe024RemovedWindowParent'),
      ['bob'],
    );
    // The original counts Charlie's plaintext copies five seconds after the
    // removed-window send.
    await Future<void>.delayed(const Duration(seconds: 5));
    s.proof['charlieRemovedWindow'] = await s.snap('charlie');
    await s.persist();
    await s.readdCharlie(name);
    for (final (label, parent, reply) in const [
      (
        'bob-reply-available',
        'aliceGe024BeforeRemovalParent',
        'bobGe024ReplyAvailable',
      ),
      (
        'bob-reply-unavailable',
        'aliceGe024RemovedWindowParent',
        'bobGe024ReplyUnavailable',
      ),
    ]) {
      await s.verbatimFlow(
        'bob',
        'production_catalog_quote_reply',
        'production_catalog_quote_reply',
        label,
        {
          'PARENT_PATTERN': pattern(parent),
          'MESSAGE': text(reply),
          'MESSAGE_PATTERN': pattern(reply),
        },
      );
      for (final receiver in ['alice', 'charlie']) {
        await s.waitWatch(
          receiver,
          '$receiver receives $reply',
          (x) => ProductionCatalogSession.rows(x, reply) == 1,
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        s.proof['got:$reply:$receiver'] = await s.snap(receiver);
      }
      await s.persist();
    }
    // Each chat renders both replies with their quote bars; Charlie never
    // held the removed-window parent, so his second quote bar reads
    // "Message unavailable".
    for (final role in ['alice', 'bob', 'charlie']) {
      final second = role == 'charlie'
          ? 'Message unavailable'
          : pattern('aliceGe024RemovedWindowParent');
      await s.flow(
        role,
        'production_catalog_assert_replies',
        '$role-renders-replies',
        {
          'FIRST_PATTERN':
              '${pattern('aliceGe024BeforeRemovalParent')}.*${pattern('bobGe024ReplyAvailable')}',
          'SECOND_PATTERN': '$second.*${pattern('bobGe024ReplyUnavailable')}',
        },
      );
    }
  },
);
