import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/resolve_contact_request_notification_target_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

typedef PresentPendingContactRequestNotificationFn =
    Future<void> Function({
      required NavigatorState navigator,
      required ContactRequestModel request,
      required Future<void> Function() onAccept,
      required Future<void> Function() onDecline,
    });

typedef OpenContactConversationFromNotificationFn =
    Future<void> Function({
      required NavigatorState navigator,
      required ContactModel contact,
    });

typedef ShowContactRequestNotificationErrorFn =
    void Function({required NavigatorState navigator, required String message});

class ContactRequestNotificationMaterializer {
  final ContactRequestRepository requestRepository;
  final ContactRepository contactRepository;
  final IdentityRepository identityRepository;
  final P2PService p2pService;
  final Bridge bridge;
  final void Function(ContactModel contact)? onProfileDownloaded;
  final PresentPendingContactRequestNotificationFn presentPendingRequest;
  final OpenContactConversationFromNotificationFn openConversation;
  final ShowContactRequestNotificationErrorFn showError;

  ContactRequestNotificationMaterializer({
    required this.requestRepository,
    required this.contactRepository,
    required this.identityRepository,
    required this.p2pService,
    required this.bridge,
    required this.presentPendingRequest,
    required this.openConversation,
    this.onProfileDownloaded,
    ShowContactRequestNotificationErrorFn? showError,
  }) : showError = showError ?? _defaultShowError;

  Future<void> handleRoute({
    required NavigatorState navigator,
    required String peerId,
  }) async {
    final target = await resolveContactRequestNotificationTarget(
      peerId: peerId,
      requestRepository: requestRepository,
      contactRepository: contactRepository,
    );

    switch (target.state) {
      case ContactRequestNotificationTargetState.pendingRequest:
        final request = target.request!;
        await presentPendingRequest(
          navigator: navigator,
          request: request,
          onAccept: () => acceptRequest(navigator: navigator, request: request),
          onDecline: () => declineRequest(request: request),
        );
        return;
      case ContactRequestNotificationTargetState.conversation:
        await openConversation(navigator: navigator, contact: target.contact!);
        return;
      case ContactRequestNotificationTargetState.missing:
        return;
    }
  }

  Future<void> acceptRequest({
    required NavigatorState navigator,
    required ContactRequestModel request,
  }) async {
    final result = await acceptAndReciprocateContactRequest(
      requestRepo: requestRepository,
      contactRepo: contactRepository,
      peerId: request.peerId,
      p2pService: p2pService,
      identityRepo: identityRepository,
      bridge: bridge,
      onProfileDownloaded: onProfileDownloaded,
    );

    if (result == AcceptContactRequestResult.success ||
        result == AcceptContactRequestResult.notPending) {
      final contact =
          await contactRepository.getContact(request.peerId) ??
          request.toContactModel();
      await openConversation(navigator: navigator, contact: contact);
      return;
    }

    showError(
      navigator: navigator,
      message: 'Unable to accept contact request',
    );
  }

  Future<void> declineRequest({required ContactRequestModel request}) async {
    await declineContactRequest(
      requestRepo: requestRepository,
      peerId: request.peerId,
    );
  }

  static void _defaultShowError({
    required NavigatorState navigator,
    required String message,
  }) {
    final context = navigator.context;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
