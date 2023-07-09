import 'package:flutter/material.dart';
import 'package:livechat/models/chat/chat.dart';
import 'package:livechat/services/isar_service.dart';
import 'package:livechat/services/notification_service.dart';
import 'package:uuid/uuid.dart';

import '../models/auth/auth_user.dart';
import '../models/chat/messages/content/content.dart';
import '../models/chat/messages/content/image_content.dart';
import '../models/chat/messages/message.dart';

class ChatProvider with ChangeNotifier {
  AuthUser? authUser;

  Map<String, Chat> _chats = {};
  String currentChat = "";

  // Called everytime AuthProvider changes
  void update(AuthUser? authUser) {
    if (authUser == null) {
      _chats.clear();
      this.authUser = null;
    } else {
      this.authUser = authUser;
      _loadChatsFromMemory();
    }
  }

  // GETTERS

  List<Message> messages(String chatName) => _chats[chatName]?.messages ?? [];

  List<Chat> chatsBySection(String section) =>
      _chats.values.where((chat) => chat.sections.contains(section)).toList();

  int get totalToRead =>
      _chats.values.fold(0, (prev, chat) => prev + chat.toRead);

  // METHODS

  void newUserChat(Map<String, dynamic> data) {
    if (!_chats.containsKey(data["username"])) {
      _chats[data["username"]] = Chat(
        chatName: data["username"],
        messages: [],
        toRead: 0,
      )..userId = authUser!.isarId;
    }

    notifyListeners();
    IsarService.instance.saveAll<Chat>(_chats.values.toList());
  }

  void addMessage(Content content, String sender, String chatName) {
    Message newMessage = Message(
      sender: sender,
      time: DateTime.now(),
      id: const Uuid().v1(),
      content: content,
    );
    _chats[chatName]?.messages.add(newMessage);

    if (currentChat != chatName) _chats[chatName]?.toRead += 1;

    if (sender != authUser!.username && currentChat != chatName) {
      NotificationService.instance.showNotification(
        id: newMessage.id!.hashCode,
        title: sender,
        body: getContentMessage(content),
        groupKey: sender,
        imagePath: content.type == ContentType.image
            ? (content as ImageContent).get().path
            : null,
      );
    }

    notifyListeners();
    IsarService.instance.insertOrUpdate<Chat>(_chats[chatName]!);
  }

  void readChat(String chatName) {
    _chats[chatName]?.toRead = 0;
    notifyListeners();
    IsarService.instance.insertOrUpdate<Chat>(_chats[chatName]!);
  }

  void updateSelectedSections(Chat chat, List<String> selectedSections) {
    chat.sections = ["All", ...selectedSections];
    notifyListeners();
    IsarService.instance.insertOrUpdate<Chat>(chat);
  }

  void _loadChatsFromMemory() async {
    List<Chat> chatsList =
        await IsarService.instance.getAll<Chat>(authUser!.isarId);

    // * Bisogna ricreare la list dei messaggi a causa di un errore di ISAR https://github.com/isar/isar/discussions/781
    _chats = {
      for (var chat in chatsList)
        chat.chatName: chat..messages = List.from(chat.messages)
    };

    // Add every new friend not in chatsList to _chats
    for (var friend in authUser!.friends
        .skipWhile((friend) => _chats.keys.contains(friend.username))) {
      _chats[friend.username] = Chat(
        chatName: friend.username,
        messages: [],
        toRead: 0,
      )..userId = authUser!.isarId;
    }

    IsarService.instance.saveAll<Chat>(_chats.values.toList());
    notifyListeners();
  }

  String getContentMessage(Content content) {
    switch (content.type) {
      case ContentType.text:
        return content.get();
      case ContentType.audio:
        return "New audio received";
      case ContentType.file:
        return "New file received";
      case ContentType.image:
        return "New media received";
    }
  }
}
