import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart' as core_fake_p2p;
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_group_pubsub_network.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/fake_media_picker.dart';
import '../test/shared/fakes/fake_p2p_network.dart';
import '../test/shared/fakes/fake_p2p_service_integration.dart' as journey_p2p;
import '../test/shared/fakes/group_test_user.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';

enum _JourneyDevice { ibra, saleh }

class _TrackingDurableMediaFileManager extends FakeMediaFileManager {
  _TrackingDurableMediaFileManager(this.rootDir);

  final Directory rootDir;

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    final extension = p.extension(sourceFilePath);
    final directory = Directory(
      p.join(rootDir.path, 'pending_uploads', messageId),
    );
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final destination = p.join(directory.path, '$attachmentId$extension');
    await File(sourceFilePath).copy(destination);
    return p.join('pending_uploads', messageId, '$attachmentId$extension');
  }

  @override
  String relativePathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) {
    return p.join('media', contactPeerId, '$blobId${_extensionForMime(mime)}');
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\')) {
      return p.join(rootDir.path, storedPath);
    }
    return storedPath;
  }

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final relativePath = relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
    final absolutePath = p.join(rootDir.path, relativePath);
    final file = File(absolutePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    return absolutePath;
  }

  @override
  Future<void> deletePendingUploadDir(String messageId) async {
    final directory = Directory(
      p.join(rootDir.path, 'pending_uploads', messageId),
    );
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

class _DownloadWritingBridge extends FakeBridge {
  _DownloadWritingBridge({required this.downloadedBytes});

  final List<int> downloadedBytes;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'media:download') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      final payload = parsed['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      final file = File(outputPath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsBytesSync(downloadedBytes, flush: true);
      return jsonEncode({
        'ok': true,
        'id': payload['id'],
        'size': downloadedBytes.length,
      });
    }

    return super.send(message);
  }
}

class _JourneyGroupBridge extends _DownloadWritingBridge {
  _JourneyGroupBridge({required super.downloadedBytes, required this.network});

  final FakeGroupPubSubNetwork network;
  dynamic groupRepo;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final senderPeerId = payload['senderPeerId'] as String;
      final latestKey = await groupRepo.getLatestKey(groupId);
      final topicPeers = network
          .getSubscribers(groupId)
          .where((peerId) => peerId != senderPeerId)
          .length;
      final envelope = <String, dynamic>{
        'groupId': groupId,
        'senderId': senderPeerId,
        'senderUsername': payload['senderUsername'] as String? ?? '',
        'keyEpoch': latestKey?.keyGeneration ?? 0,
        'text': payload['text'] as String? ?? '',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'messageId': payload['messageId'] as String,
      };
      if (payload['quotedMessageId'] is String &&
          (payload['quotedMessageId'] as String).isNotEmpty) {
        envelope['quotedMessageId'] = payload['quotedMessageId'];
      }
      if (payload['media'] is List<dynamic>) {
        envelope['media'] = payload['media'] as List<dynamic>;
      }

      await network.publish(groupId, senderPeerId, envelope);
      return jsonEncode({
        'ok': true,
        'messageId': payload['messageId'] as String,
        'topicPeers': topicPeers,
      });
    }

    return super.send(message);
  }
}

class _JourneyChatUser {
  _JourneyChatUser._({
    required this.peerId,
    required this.username,
    required this.identity,
    required this.identityRepo,
    required this.bridge,
    required this.p2pService,
    required this.messageRepo,
    required this.contactRepo,
    required this.mediaAttachmentRepo,
    required this.mediaFileManager,
    required this.chatListener,
  });

  final String peerId;
  final String username;
  final IdentityModel identity;
  final FakeIdentityRepository identityRepo;
  final _DownloadWritingBridge bridge;
  final journey_p2p.FakeP2PService p2pService;
  final InMemoryMessageRepository messageRepo;
  final InMemoryContactRepository contactRepo;
  final InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  final _TrackingDurableMediaFileManager mediaFileManager;
  final ChatMessageListener chatListener;

  factory _JourneyChatUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
    required _DownloadWritingBridge bridge,
    required _TrackingDurableMediaFileManager mediaFileManager,
  }) {
    final identity = _makeIdentity(peerId: peerId, username: username);
    final identityRepo = FakeIdentityRepository()..seed(identity);
    final messageRepo = InMemoryMessageRepository();
    final contactRepo = InMemoryContactRepository();
    final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    final p2pService = journey_p2p.FakeP2PService(
      peerId: peerId,
      network: network,
    );
    final chatListener = ChatMessageListener(
      chatMessageStream: p2pService.messageStream,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
    return _JourneyChatUser._(
      peerId: peerId,
      username: username,
      identity: identity,
      identityRepo: identityRepo,
      bridge: bridge,
      p2pService: p2pService,
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      chatListener: chatListener,
    );
  }

  void addContact(_JourneyChatUser other) {
    contactRepo.addTestContact(
      _makeContact(peerId: other.peerId, username: other.username),
    );
  }

  void start() => chatListener.start();

  void dispose() {
    chatListener.dispose();
    p2pService.dispose();
  }
}

class _JourneyHarness {
  _JourneyHarness({
    required this.rootDir,
    required this.oneToOneImage,
    required this.groupImage,
    required this.ibraToSalehContact,
    required this.salehToIbraContact,
    required this.ibraChatUser,
    required this.salehChatUser,
    required this.ibraGroupUser,
    required this.salehGroupUser,
    required this.ibraGroup,
    required this.salehGroup,
    required this.ibraMediaPicker,
    required this.salehMediaPicker,
  });

  final Directory rootDir;
  final File oneToOneImage;
  final File groupImage;
  final ContactModel ibraToSalehContact;
  final ContactModel salehToIbraContact;
  final _JourneyChatUser ibraChatUser;
  final _JourneyChatUser salehChatUser;
  final GroupTestUser ibraGroupUser;
  final GroupTestUser salehGroupUser;
  final GroupModel ibraGroup;
  final GroupModel salehGroup;
  final FakeMediaPicker ibraMediaPicker;
  final FakeMediaPicker salehMediaPicker;

  static Future<_JourneyHarness> create() async {
    final rootDir = await Directory.systemTemp.createTemp('media_journey_e2e_');
    final ibraDir = Directory(p.join(rootDir.path, 'ibra'))..createSync();
    final salehDir = Directory(p.join(rootDir.path, 'saleh'))..createSync();
    final oneToOneImage = await _writePngFixture(
      rootDir,
      'ibra_to_saleh_journey.png',
    );
    final groupImage = await _writePngFixture(
      rootDir,
      'ibra_group_journey.png',
    );
    final downloadBytes = _minimalPngBytes();

    final oneToOneNetwork = FakeP2PNetwork();
    final ibraChatBridge = _DownloadWritingBridge(
      downloadedBytes: downloadBytes,
    );
    final salehChatBridge = _DownloadWritingBridge(
      downloadedBytes: downloadBytes,
    );
    final ibraChatUser = _JourneyChatUser.create(
      peerId: 'peer-ibra',
      username: 'Ibra',
      network: oneToOneNetwork,
      bridge: ibraChatBridge,
      mediaFileManager: _TrackingDurableMediaFileManager(ibraDir),
    );
    final salehChatUser = _JourneyChatUser.create(
      peerId: 'peer-saleh',
      username: 'Saleh',
      network: oneToOneNetwork,
      bridge: salehChatBridge,
      mediaFileManager: _TrackingDurableMediaFileManager(salehDir),
    );
    ibraChatUser.addContact(salehChatUser);
    salehChatUser.addContact(ibraChatUser);
    ibraChatUser.start();
    salehChatUser.start();

    final groupNetwork = FakeGroupPubSubNetwork();
    final ibraGroupBridge = _JourneyGroupBridge(
      downloadedBytes: downloadBytes,
      network: groupNetwork,
    );
    final salehGroupBridge = _JourneyGroupBridge(
      downloadedBytes: downloadBytes,
      network: groupNetwork,
    );
    final ibraGroupUser = GroupTestUser.create(
      peerId: ibraChatUser.peerId,
      username: ibraChatUser.username,
      network: groupNetwork,
      bridge: ibraGroupBridge,
      mediaFileManager: ibraChatUser.mediaFileManager,
    );
    ibraGroupBridge.groupRepo = ibraGroupUser.groupRepo;
    final salehGroupUser = GroupTestUser.create(
      peerId: salehChatUser.peerId,
      username: salehChatUser.username,
      network: groupNetwork,
      bridge: salehGroupBridge,
      mediaFileManager: salehChatUser.mediaFileManager,
    );
    salehGroupBridge.groupRepo = salehGroupUser.groupRepo;

    final ibraGroup = await ibraGroupUser.createGroup(
      groupId: 'group-media-journey',
      name: 'Media Journey',
    );
    await ibraGroupUser.addMember(
      groupId: ibraGroup.id,
      invitee: salehGroupUser,
    );
    await _saveGroupKey(ibraGroupUser, ibraGroup.id, 1, 'journey-group-key');
    await _saveGroupKey(salehGroupUser, ibraGroup.id, 1, 'journey-group-key');
    ibraGroupUser.start();
    salehGroupUser.start();
    final salehGroup = await salehGroupUser.groupRepo.getGroup(ibraGroup.id);
    if (salehGroup == null) {
      throw StateError('Missing Saleh group projection for ${ibraGroup.id}');
    }

    final ibraMediaPicker = FakeMediaPicker()
      ..multipleMediaResult = [XFile(oneToOneImage.path)];
    final salehMediaPicker = FakeMediaPicker()
      ..multipleMediaResult = [XFile(groupImage.path)];

    return _JourneyHarness(
      rootDir: rootDir,
      oneToOneImage: oneToOneImage,
      groupImage: groupImage,
      ibraToSalehContact: _makeContact(
        peerId: salehChatUser.peerId,
        username: salehChatUser.username,
      ),
      salehToIbraContact: _makeContact(
        peerId: ibraChatUser.peerId,
        username: ibraChatUser.username,
      ),
      ibraChatUser: ibraChatUser,
      salehChatUser: salehChatUser,
      ibraGroupUser: ibraGroupUser,
      salehGroupUser: salehGroupUser,
      ibraGroup: ibraGroup,
      salehGroup: salehGroup,
      ibraMediaPicker: ibraMediaPicker,
      salehMediaPicker: salehMediaPicker,
    );
  }

  _JourneyChatUser chatUserFor(_JourneyDevice device) {
    return device == _JourneyDevice.ibra ? ibraChatUser : salehChatUser;
  }

  _JourneyChatUser otherChatUserFor(_JourneyDevice device) {
    return device == _JourneyDevice.ibra ? salehChatUser : ibraChatUser;
  }

  ContactModel contactFor(_JourneyDevice device) {
    return device == _JourneyDevice.ibra
        ? ibraToSalehContact
        : salehToIbraContact;
  }

  GroupTestUser groupUserFor(_JourneyDevice device) {
    return device == _JourneyDevice.ibra ? ibraGroupUser : salehGroupUser;
  }

  GroupModel groupFor(_JourneyDevice device) {
    return device == _JourneyDevice.ibra ? ibraGroup : salehGroup;
  }

  FakeMediaPicker mediaPickerFor(_JourneyDevice device) {
    return device == _JourneyDevice.ibra ? ibraMediaPicker : salehMediaPicker;
  }

  void dispose() {
    ibraChatUser.dispose();
    salehChatUser.dispose();
    ibraGroupUser.dispose();
    salehGroupUser.dispose();
    if (rootDir.existsSync()) {
      rootDir.deleteSync(recursive: true);
    }
  }
}

class _JourneyHarnessApp extends StatefulWidget {
  const _JourneyHarnessApp({required this.harness});

  final _JourneyHarness harness;

  @override
  State<_JourneyHarnessApp> createState() => _JourneyHarnessAppState();
}

class _JourneyHarnessAppState extends State<_JourneyHarnessApp> {
  _JourneyDevice _activeDevice = _JourneyDevice.ibra;
  final _navigatorKey = GlobalKey<NavigatorState>();

  _JourneyChatUser get _chatUser => widget.harness.chatUserFor(_activeDevice);
  _JourneyChatUser get _otherChatUser =>
      widget.harness.otherChatUserFor(_activeDevice);
  GroupTestUser get _groupUser => widget.harness.groupUserFor(_activeDevice);

  void _switchDevice(_JourneyDevice device) {
    setState(() {
      _activeDevice = device;
    });
  }

  void _openConversation() {
    _navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => _buildConversation()),
    );
  }

  void _openGroup() {
    _navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => _buildGroup()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    return Scaffold(
      appBar: AppBar(title: const Text('Media Journey Harness')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Device focus',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const Key('device-ibra'),
                label: const Text('Ibra'),
                selected: _activeDevice == _JourneyDevice.ibra,
                onSelected: (_) => _switchDevice(_JourneyDevice.ibra),
              ),
              ChoiceChip(
                key: const Key('device-saleh'),
                label: const Text('Saleh'),
                selected: _activeDevice == _JourneyDevice.saleh,
                onSelected: (_) => _switchDevice(_JourneyDevice.saleh),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Focused device: ${_chatUser.username}',
            key: const Key('focused-device-label'),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          ListTile(
            key: const Key('open-one-to-one-thread'),
            title: Text('Chat with ${_otherChatUser.username}'),
            subtitle: const Text('Real compose area + fake media picker'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openConversation,
          ),
          ListTile(
            key: const Key('open-group-thread'),
            title: const Text('Group: Media Journey'),
            subtitle: const Text('Real group compose + media delivery'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openGroup,
          ),
        ],
      ),
    );
  }

  Widget _buildConversation() {
    return ConversationWired(
      contact: widget.harness.contactFor(_activeDevice),
      identityRepo: _chatUser.identityRepo,
      messageRepo: _chatUser.messageRepo,
      chatMessageListener: _chatUser.chatListener,
      p2pService: _chatUser.p2pService,
      bridge: _chatUser.bridge,
      contactRepo: _chatUser.contactRepo,
      mediaAttachmentRepo: _chatUser.mediaAttachmentRepo,
      mediaFileManager: _chatUser.mediaFileManager,
      mediaPicker: widget.harness.mediaPickerFor(_activeDevice),
      uploadMediaFn:
          ({
            required bridge,
            required localFilePath,
            required mime,
            required recipientPeerId,
            mediaFileManager,
            width,
            height,
            durationMs,
            waveform,
            allowedPeers,
            blobId,
          }) async => MediaAttachment(
            id: blobId ?? 'blob-${DateTime.now().microsecondsSinceEpoch}',
            messageId: '',
            mime: mime,
            size: await File(localFilePath).length(),
            mediaType: MediaAttachment.mediaTypeFromMime(mime),
            localPath: localFilePath,
            downloadStatus: 'done',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            width: width,
            height: height,
            durationMs: durationMs,
            waveform: waveform,
          ),
      sendChatMessageFn: sendChatMessage,
      deleteContactFn: (_) async {},
    );
  }

  Widget _buildGroup() {
    final user = _groupUser;
    return GroupConversationWired(
      group: widget.harness.groupFor(_activeDevice),
      groupRepo: user.groupRepo,
      msgRepo: user.msgRepo,
      groupMessageListener: user.groupMessageListener,
      bridge: user.bridge,
      identityRepo: _chatUser.identityRepo,
      contactRepo: InMemoryContactRepository(),
      p2pService: core_fake_p2p.FakeP2PService(
        initialState: NodeState(isStarted: true, peerId: user.peerId),
      ),
      mediaAttachmentRepo: user.mediaAttachmentRepo,
      mediaFileManager: _chatUser.mediaFileManager,
      mediaPicker: widget.harness.mediaPickerFor(_activeDevice),
      uploadMediaFn:
          ({
            required bridge,
            required localFilePath,
            required mime,
            required recipientPeerId,
            mediaFileManager,
            width,
            height,
            durationMs,
            waveform,
            allowedPeers,
            blobId,
          }) async => MediaAttachment(
            id: blobId ?? 'blob-${DateTime.now().microsecondsSinceEpoch}',
            messageId: '',
            mime: mime,
            size: await File(localFilePath).length(),
            mediaType: MediaAttachment.mediaTypeFromMime(mime),
            localPath: localFilePath,
            downloadStatus: 'done',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            width: width,
            height: height,
            durationMs: durationMs,
            waveform: waveform,
          ),
    );
  }
}

ContactModel _makeContact({required String peerId, required String username}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
  );
}

IdentityModel _makeIdentity({
  required String peerId,
  required String username,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return IdentityModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    privateKey: 'sk-$peerId',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    username: username,
    createdAt: now,
    updatedAt: now,
  );
}

List<int> _minimalPngBytes() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAAlwSFlzAAAuIwAALiMBeKU/dgAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KTMInWQAAAdVJREFUOBF9Uz1PG0EQfXt3PoNEYgrCh4AiSEnhICQLI0qoqHGN6PIDEE0qmqSNlCapwg9ImTpFAjYIR5DQuECyEFKk2HJhLEJxyN69zcyd116fE29xuzu7772Zt3NC08CIYZ8KMXzRGw71IwxOgpKx/xKEBHZI8aKh8PM2BO+n0sD20xQ8OxMuITlUGEfKNanXjgPtfQ104eRB1+5VdBB2z3kj+NNPGpESK5frCvvVDjK0eU7Kr1d8ZNKid24wjlnwbNL+boEXU8DBcgzuhHFZNqaXgTGHwXukPEnK8wR+l/PxyLeLtuFkMpdgwKXfEq+uZQSeJXvfr/qQpFppKqRdAUnF5p448GltxkAJbMaZAjjtD3kfbVq//NHG1pVEvtKJSmSw7VqvBMNYrks8m3ThUmCzGGB63EHGd3GwJLAy7YFF+vrdEgzYmPhAub74EuBOuGgqhaNsiI2lCXRUiJQ7kDQGdvx8TDJGnXKY9dFsS+qkU3z6+BmtP0EEph4wevEcm5j4djvl2+UvjYU3Gt5bPbdzqGuNVnQxtDppyAOmZQ1+God+hNJ5FcWLG0hKf3HmMXYL60h5bs+LfxLEucVEtmEcpy6OiM2dkQQGYEhE8tekC38BADIeNqhZl4wAAAAASUVORK5CYII=',
  );
}

String _extensionForMime(String mime) {
  if (mime == 'image/png') return '.png';
  if (mime == 'image/jpeg') return '.jpg';
  if (mime == 'audio/mp4' || mime == 'audio/x-m4a') return '.m4a';
  if (mime == 'audio/mpeg') return '.mp3';
  if (mime == 'video/mp4') return '.mp4';
  return '';
}

Future<File> _writePngFixture(Directory tempDir, String name) async {
  final file = File(p.join(tempDir.path, name));
  await file.writeAsBytes(_minimalPngBytes(), flush: true);
  return file;
}

Future<void> _saveGroupKey(
  GroupTestUser user,
  String groupId,
  int keyGeneration,
  String encryptedKey,
) async {
  await user.groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: keyGeneration,
      encryptedKey: encryptedKey,
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 12}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 8),
  Duration step = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      await tester.pump(step);
      return;
    }
    await tester.pump(step);
  }
  expect(await condition(), isTrue, reason: 'Condition was not met in time');
}

Future<void> _selectDevice(WidgetTester tester, _JourneyDevice device) async {
  await _pumpUntilAsync(tester, () async {
    return find
        .byKey(const Key('open-one-to-one-thread'))
        .evaluate()
        .isNotEmpty;
  });
  final target = find.byKey(
    device == _JourneyDevice.ibra
        ? const Key('device-ibra')
        : const Key('device-saleh'),
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _pumpFrames(tester, count: 6);
}

Future<void> _openThread(WidgetTester tester, {required bool group}) async {
  await _pumpUntilAsync(tester, () async {
    return find
            .byKey(const Key('open-one-to-one-thread'))
            .evaluate()
            .isNotEmpty &&
        find.byKey(const Key('open-group-thread')).evaluate().isNotEmpty;
  });
  final target = find.byKey(
    group
        ? const Key('open-group-thread')
        : const Key('open-one-to-one-thread'),
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _pumpFrames(tester);
}

Future<void> _attachImageFromLibrary(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_rounded));
  await _pumpFrames(tester, count: 4);
  await tester.tap(find.widgetWithText(ListTile, 'Media Library'));
  await _pumpFrames(tester, count: 10);
}

Future<void> _sendTextAndImage(
  WidgetTester tester, {
  required String text,
}) async {
  await _attachImageFromLibrary(tester);
  expect(find.byType(MediaGrid), findsNothing);
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _leaveThread(WidgetTester tester) async {
  bool homeVisible() {
    return find
            .byKey(const Key('open-one-to-one-thread'))
            .evaluate()
            .isNotEmpty &&
        find.byKey(const Key('open-group-thread')).evaluate().isNotEmpty;
  }

  final groupHeader = find.byKey(const ValueKey('group-header'));
  final conversationBack = find.byIcon(Icons.chevron_left);
  final groupBack = find.byIcon(Icons.arrow_back_ios_new);
  if (groupHeader.evaluate().isNotEmpty && groupBack.evaluate().isNotEmpty) {
    await tester.tap(groupBack);
  } else if (conversationBack.evaluate().isNotEmpty) {
    await tester.tap(conversationBack);
  } else if (groupBack.evaluate().isNotEmpty) {
    await tester.tap(groupBack);
  } else {
    fail('No visible back control found for the current thread.');
  }
  await _pumpFrames(tester, count: 8);
  if (!homeVisible()) {
    await _pumpUntilAsync(
      tester,
      () async => homeVisible(),
      timeout: const Duration(seconds: 3),
    );
  }
}

Future<void> _expectVisibleMediaMessage(
  WidgetTester tester, {
  required String text,
}) async {
  await _pumpUntilAsync(tester, () async {
    final hasText = find.text(text).evaluate().isNotEmpty;
    final hasGrid = find.byType(MediaGrid).evaluate().isNotEmpty;
    final hasBroken = find
        .descendant(
          of: find.byType(MediaGrid),
          matching: find.byIcon(Icons.broken_image_outlined),
        )
        .evaluate()
        .isNotEmpty;
    return hasText && hasGrid && !hasBroken;
  });
  expect(find.text(text), findsWidgets);
  expect(find.byType(MediaGrid), findsWidgets);
  expect(
    find.descendant(
      of: find.byType(MediaGrid),
      matching: find.byIcon(Icons.broken_image_outlined),
    ),
    findsNothing,
  );
}

Future<void> _waitForOneToOneDelivery(
  WidgetTester tester,
  _JourneyHarness harness, {
  required String text,
}) async {
  await _pumpUntilAsync(tester, () async {
    final ibraMessages = await harness.ibraChatUser.messageRepo
        .getMessagesForContact(harness.salehChatUser.peerId);
    final salehMessages = await harness.salehChatUser.messageRepo
        .getMessagesForContact(harness.ibraChatUser.peerId);
    final ibraMessage = ibraMessages.where(
      (m) => !m.isIncoming && m.text == text,
    );
    final salehMessage = salehMessages.where(
      (m) => m.isIncoming && m.text == text,
    );
    if (ibraMessage.isEmpty || salehMessage.isEmpty) {
      return false;
    }
    final ibraAttachments = await harness.ibraChatUser.mediaAttachmentRepo
        .getAttachmentsForMessage(ibraMessage.last.id);
    final salehAttachments = await harness.salehChatUser.mediaAttachmentRepo
        .getAttachmentsForMessage(salehMessage.last.id);
    return ibraAttachments.length == 1 && salehAttachments.length == 1;
  });
}

Future<void> _waitForGroupDelivery(
  WidgetTester tester,
  _JourneyHarness harness, {
  required String text,
}) async {
  await _pumpUntilAsync(tester, () async {
    final ibraMessages = await harness.ibraGroupUser.msgRepo.getMessagesPage(
      harness.ibraGroup.id,
      limit: 100,
    );
    final salehMessages = await harness.salehGroupUser.msgRepo.getMessagesPage(
      harness.ibraGroup.id,
      limit: 100,
    );
    final ibraMessage = ibraMessages.where(
      (m) => !m.isIncoming && m.text == text,
    );
    final salehMessage = salehMessages.where(
      (m) => m.isIncoming && m.text == text,
    );
    if (ibraMessage.isEmpty || salehMessage.isEmpty) {
      return false;
    }
    final ibraAttachments = await harness.ibraGroupUser.mediaAttachmentRepo
        .getAttachmentsForMessage(ibraMessage.last.id);
    final salehAttachments = await harness.salehGroupUser.mediaAttachmentRepo
        .getAttachmentsForMessage(salehMessage.last.id);
    return ibraAttachments.length == 1 && salehAttachments.length == 1;
  });
}

void _logStep(String message) {
  // Printed steps make emulator runs easier to follow live.
  // ignore: avoid_print
  print('[MEDIA_JOURNEY] $message');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Media message journey E2E', () {
    testWidgets(
      'real compose journeys render media for sender and receiver in 1:1 and group threads',
      (tester) async {
        final harness = await _JourneyHarness.create();
        addTearDown(harness.dispose);

        await tester.pumpWidget(_JourneyHarnessApp(harness: harness));
        await _pumpFrames(tester);

        const oneToOneText = 'Photo from Ibra to Saleh';
        const groupText = 'Group photo from Ibra';

        _logStep('Ibra opens the 1:1 thread and sends an image');
        await _selectDevice(tester, _JourneyDevice.ibra);
        harness.ibraMediaPicker.multipleMediaResult = [
          XFile(harness.oneToOneImage.path),
        ];
        await _openThread(tester, group: false);
        await _sendTextAndImage(tester, text: oneToOneText);
        await _leaveThread(tester);

        _logStep(
          'Background delivery settles while both thread UIs are closed',
        );
        await _waitForOneToOneDelivery(tester, harness, text: oneToOneText);

        _logStep(
          'Ibra reopens the 1:1 thread and verifies the outgoing bubble',
        );
        await _openThread(tester, group: false);
        await _expectVisibleMediaMessage(tester, text: oneToOneText);
        await _leaveThread(tester);

        _logStep('Saleh opens the 1:1 thread and verifies the incoming image');
        await _selectDevice(tester, _JourneyDevice.saleh);
        await _openThread(tester, group: false);
        await _expectVisibleMediaMessage(tester, text: oneToOneText);
        await _leaveThread(tester);

        _logStep('Ibra opens the group thread and sends an image');
        await _selectDevice(tester, _JourneyDevice.ibra);
        harness.ibraMediaPicker.multipleMediaResult = [
          XFile(harness.groupImage.path),
        ];
        await _openThread(tester, group: true);
        await _sendTextAndImage(tester, text: groupText);
        await _leaveThread(tester);

        _logStep('Group delivery settles after the sender leaves immediately');
        await _waitForGroupDelivery(tester, harness, text: groupText);

        _logStep(
          'Ibra reopens the group thread and verifies the outgoing image',
        );
        await _openThread(tester, group: true);
        await _expectVisibleMediaMessage(tester, text: groupText);
        await _leaveThread(tester);

        _logStep(
          'Saleh opens the group thread and verifies the incoming image',
        );
        await _selectDevice(tester, _JourneyDevice.saleh);
        await _openThread(tester, group: true);
        await _expectVisibleMediaMessage(tester, text: groupText);
      },
    );
  });
}
