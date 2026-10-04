import '../../tool/sims/production_group_up012_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_removed_notification_privacy',
  validatorId: 'validateProductionGroupUp012',
  texts: productionUp012Texts,
  validate: validateProductionGroupUp012,
  steps: (s) async {
    final texts = productionUp012Texts(s.journey.runId);
    String text(String key) => texts[key]!.text;
    await s.createAndAcceptAll(
      s.catalogName('private_removed_notification_privacy'),
    );
    final groupId = (await s.snap('alice'))['groupId'] as String;
    s.proof['charlieBefore'] = await s.waitWatch(
      'charlie',
      'Charlie current member before removal',
      (x) => x['selfMember'] == true,
    );
    await s.removeCharlie();
    await s.rotatedForRemainingPair();
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');

    // Each receiver is away from the chat when the other posts, so its app
    // shows a real notification for that post.
    await s.flow('alice', 'production_home_tabs', 'alice-home');
    await s.sendAndReceive(
      'bob',
      'bob-after-remove',
      'bobAfterCharlieRemove',
      text('bobAfterCharlieRemove'),
      ['alice'],
    );
    await s.waitWatch(
      'alice',
      'Alice shows a notification',
      (x) => ((x['notifications'] as List?) ?? const []).isNotEmpty,
    );
    await s.flow('alice', 'production_group_open', 'alice-open-group', {
      'GROUP_ID': groupId,
    });
    await s.flow('bob', 'production_home_tabs', 'bob-home');
    await s.sendAndReceive(
      'alice',
      'alice-after-remove',
      'aliceAfterCharlieRemove',
      text('aliceAfterCharlieRemove'),
      ['bob'],
    );
    await s.waitWatch(
      'bob',
      'Bob shows a notification',
      (x) => ((x['notifications'] as List?) ?? const []).isNotEmpty,
    );
    // The original's five-second absence window before counting leaks.
    await Future<void>.delayed(const Duration(seconds: 5));
  },
);
